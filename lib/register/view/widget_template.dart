import 'package:flutter/material.dart';

class WidgetTemplate extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final int? maxLength;

  const WidgetTemplate({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: label,
          counterText: '',
        ),
      ),
    );
  }
}
