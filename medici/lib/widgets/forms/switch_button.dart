import 'package:flutter/material.dart';

class SwitchButton extends StatefulWidget {
  const SwitchButton(
      {super.key,
      required this.label,
      required this.requiredField,
      required this.callback,
      this.initialValue});

  final String label;
  final bool requiredField;
  final bool? initialValue;
  final Function callback;

  @override
  State<SwitchButton> createState() => _SwitchButton();
}

class _SwitchButton extends State<SwitchButton> {
  late bool enable;

  @override
  void initState() {
    super.initState();
    try {
      enable = widget.initialValue!;
    } catch (error) {
      enable = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    void _onChange(bool value) {
      setState(() {
        enable = value;
      });

      widget.callback(value);
    }

    return Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(widget.requiredField ? widget.label + "*" : widget.label,
                style: const TextStyle(fontSize: 16)),
            Switch(
                value: enable, activeColor: Colors.green, onChanged: _onChange)
          ],
        ));
  }
}
