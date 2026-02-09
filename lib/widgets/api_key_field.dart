import 'package:flutter/material.dart';

class ApiKeyField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final Function(String) onChanged;

  const ApiKeyField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    required this.onChanged,
  });

  @override
  State<ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<ApiKeyField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.maxLines == 1;
  }

  @override
  Widget build(BuildContext context) {
    final canObscure = widget.maxLines == 1;
    
    return TextField(
      controller: widget.controller,
      obscureText: canObscure && _obscureText,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIcon: canObscure 
          ? IconButton(
              icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureText = !_obscureText),
            )
          : null,
      ),
      onChanged: widget.onChanged,
    );
  }
}
