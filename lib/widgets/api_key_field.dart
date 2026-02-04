import 'package:flutter/material.dart';

class ApiKeyField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final Function(String) onChanged;

  const ApiKeyField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  @override
  State<ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<ApiKeyField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
