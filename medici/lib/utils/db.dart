import 'package:medici/models/alert.dart';
import 'package:medici/models/drug.dart';
import 'package:medici/models/notification_settings.dart';
import 'package:medici/utils/alerts.dart';
import 'package:medici/utils/debug.dart';
import 'package:medici/utils/notifications.dart';
import 'package:medici/utils/time.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DB {
  Database? database;

  Future<void> getDB() async {
    if (database != null) return;

    database = await openDatabase(join(await getDatabasesPath(), 'data.db'),
        onCreate: (db, version) {
      db.execute('''
        CREATE TABLE drug (
          id INTEGER PRIMARY KEY AUTOINCREMENT, 
          name TEXT NOT NULL, 
          image TEXT, 
          expiration_date INTEGER NOT NULL, 
          last_day INTEGER, 
          quantity REAL NOT NULL, 
          dose_type TEXT NOT NULL, 
          dose REAL NOT NULL, 
          recurrent INTEGER NOT NULL,
          leaflet TEXT,
          status TEXT NOT NULL,
          frequency TEXT NOT NULL,
          starting_time TEXT NOT NULL)
      ''');

      db.execute('''
        CREATE TABLE alert(
          id INTEGER PRIMARY KEY AUTOINCREMENT, 
          time TEXT NOT NULL,
          drug_id INTEGER NOT NULL,
          status TEXT NOT NULL,
          last_interaction TEXT NOT NULL,
          FOREIGN KEY(drug_id) REFERENCES drug(id)
        )
      ''');

      db.execute('''
        CREATE TABLE notification(
          id INTEGER PRIMARY KEY AUTOINCREMENT, 
          expiration_offset INTEGER NOT NULL,
          quantity_offset INTEGER NOT NULL,
          drug_id INTEGER NOT NULL,
          FOREIGN KEY(drug_id) REFERENCES drug(id)
        )
      ''');
    }, version: 1);
  }

  Future<int> addDrug(Drug drug) async {
    await getDB();

    int id = await database!.insert('drug', drug.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail);

    return id;
  }

  Future<int> addNotification(NotificationSettings notification) async {
    await getDB();

    int id = await database!.insert('notification', notification.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail);
    return id;
  }

  Future<List<int>> addAlerts(List<Alert> alerts) async {
    await getDB();

    List<int> ids = [];

    for (Alert alert in alerts) {
      int id = await database!.insert('alert', alert.toMap(),
          conflictAlgorithm: ConflictAlgorithm.fail);
      ids.add(id);
    }

    return ids;
  }

  Future<List<DrugsScheduling>> getDrugs(
      NotificationService notifications) async {
    await getDB();

    final data = await database!.rawQuery('''
      SELECT 
        alert.id as alert_id,
        alert.time,
        alert.status as alert_status,
        alert.last_interaction,
        drug.id as drug_id,
        drug.last_day,
        drug.name, 
        drug.image, 
        drug.dose_type, 
        drug.dose,
        drug.status as drug_status,
        drug.quantity
      FROM alert 
      INNER JOIN drug ON drug.id = alert.drug_id
      WHERE drug.status != 'archived' AND alert.status != 'aware' AND alert.status != 'taken';
    ''');

    List<DrugsScheduling> drugs = [];
    for (final drug in data) {
      final String lastDay = drug['last_day'] as String;
      final int id = drug['drug_id'] as int;
      final int alertId = drug['alert_id'] as int;

      if (equalDate(DateTime.now(), parseStringDate(lastDay))) {
        await archiveDrug(id);
        await notifications.cancelNotification(alertId);
        continue;
      }

      final String time = drug['time'] as String;
      final String lastInteraction = drug['last_interaction'] as String;

      String status = 'pending';

      if (passedAtLeastOneDay(parseStringDate(lastInteraction))) {
        await updateAlertStatus(alertId, 'pending');
      } else {
        status = getAlertStatus(time);
        final String lastStatus = drug['alert_status'] as String;

        if (lastStatus == 'pending') {
          await updateAlertStatus(alertId, status);
        }
      }

      drugs.add(DrugsScheduling(
          id: id,
          name: drug['name'] as String,
          doseType: drug['dose_type'] as String,
          dose: drug['dose'] as double,
          image: drug['image'] as String?,
          status: drug['drug_status'] as String,
          quantity: drug['quantity'] as double,
          alert: Alert(
              id: drug['alert_id'] as int,
              drugId: id,
              status: status,
              time: time,
              lastInteraction: lastInteraction)));
    }

    return drugs;
  }

  Future<List<DrugTinyData>> getAllDrugs() async {
    await getDB();

    final data =
        await database!.query('drug', columns: ['id', 'name', 'image']);

    List<DrugTinyData> drugs = [];
    for (final drug in data) {
      drugs.add(DrugTinyData(
          id: drug['id'] as int,
          name: drug['name'] as String,
          image: drug['image'] as String?));
    }

    return drugs;
  }

  Future<FullDrug> getFullDrugData(int id) async {
    await getDB();

    simpleLog("Getting Full Drug Data");

    final drugData =
        (await database!.query('drug', where: 'id=?', whereArgs: [id])).first;
    final notificationData = (await database!
            .query('notification', where: 'drug_id=?', whereArgs: [id]))
        .first;
    final alertsData =
        await database!.query('alert', where: 'drug_id=?', whereArgs: [id]);

    final List<Alert> alerts = alertsData
        .map((data) => Alert(
            drugId: data['drug_id'] as int,
            lastInteraction: data['last_interaction'] as String,
            status: data['status'] as String,
            time: data['time'] as String,
            id: data['id'] as int))
        .toList();

    final notification = NotificationSettings(
        drugId: notificationData['drug_id'] as int,
        expirationOffset: notificationData['expiration_offset'] as int,
        quantityOffset: notificationData['quantity_offset'] as int,
        id: notificationData['id'] as int);

    FullDrug drug = FullDrug(
        dose: drugData['dose'] as double,
        doseType: drugData['dose_type'] as String,
        expirationDate: drugData['expiration_date'] as String,
        name: drugData['name'] as String,
        id: id,
        quantity: drugData['quantity'] as double,
        recurrent: drugData['recurrent'] == 1,
        image: drugData['image'] as String?,
        lastDay: drugData['last_day'] as String?,
        leaflet: drugData['leaflet'] as String?,
        status: drugData['status'] as String,
        frequency: drugData['frequency'] as String,
        startingTime: drugData['starting_time'] as String,
        notification: notification,
        schedule: alerts);

    successLog("Got all data!");

    return drug;
  }

  Future<void> deleteDrug(int id) async {
    await getDB();

    await database!.delete('notification', where: 'drug_id=?', whereArgs: [id]);
    await database!.delete('alert', where: 'drug_id=?', whereArgs: [id]);
    await database!.delete('drug', where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteAlerts(int drugId) async {
    await getDB();
    await database!.delete('alert', where: 'drug_id=?', whereArgs: [drugId]);
  }

  Future<void> deleteNotificationSettings(int drugId) async {
    await getDB();
    await database!
        .delete('notification', where: 'drug_id=?', whereArgs: [drugId]);
  }

  Future<void> archiveDrug(int id) async {
    await getDB();

    await database!.update('drug', {'status': 'archived'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> unarchiveDrug(int id) async {
    await getDB();

    await database!.update('drug', {'status': 'current'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateDrug(Drug drug) async {
    await getDB();

    await database!.update('drug', drug.toMap(),
        where: 'id=?',
        whereArgs: [drug.id],
        conflictAlgorithm: ConflictAlgorithm.fail);
  }

  Future<void> reduceQuantity(
      int id, int alertId, NotificationService notification) async {
    await getDB();

    final alertData = (await database!.query('alert',
            columns: ['status'], where: 'id=?', whereArgs: [alertId]))
        .first;

    if (alertData.isEmpty) throw Exception('Invalid Alert data');

    final String status = alertData['status'] as String;
    if (status == 'taken') return;

    final drugData = (await database!.query('drug',
            columns: ['quantity', 'dose', 'name'],
            where: 'id=?',
            whereArgs: [id]))
        .first;

    final notificationData = (await database!.query('notification',
            columns: ['quantity_offset'], where: 'drug_id=?', whereArgs: [id]))
        .first;

    final String drugName = drugData['name'] as String;

    final double quantity = drugData['quantity'] as double;
    final double dose = drugData['dose'] as double;
    final int quantityOffset = notificationData['quantity_offset'] as int;

    final double updatedQuantity = quantity - dose;
    final double newQuantity = updatedQuantity <= 0 ? 0 : updatedQuantity;

    if (newQuantity <= quantityOffset) {
      await notification.showQuantityNotification(id, drugName);
    }

    await database!.rawUpdate('''
      UPDATE drug
      SET 
        quantity = ?
      WHERE id=?;
    ''', [newQuantity, id]);
  }

  Future<void> refillDrugAmount(int id, double amount) async {
    await getDB();

    await database!
        .update('drug', {'quantity': amount}, where: 'id=?', whereArgs: [id]);
  }

  Future<void> updateAlertStatus(int id, String status) async {
    await getDB();

    simpleLog("updating alert $id to status $status");

    await database!.update('alert',
        {'status': status, 'last_interaction': buildDateString(DateTime.now())},
        where: 'id=?',
        whereArgs: [id],
        conflictAlgorithm: ConflictAlgorithm.fail);

    successLog("Updated!");
  }

  Future<void> close() async {
    database?.close();
  }
}
