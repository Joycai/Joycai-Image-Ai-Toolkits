import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// A secret-entry field: obscured by default with a reveal toggle, for API
/// keys and other single-line credentials.
///
/// Built on [AppTextField] so it picks up the app's input styling; this
/// widget only adds the obscure/reveal behaviour on top.
class ApiKeyField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final Function(String) onChanged;

  /// Validation message shown under the field, which also turns its border
  /// and label red — the "this provider needs a key" state.
  final String? errorText;

  const ApiKeyField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    required this.onChanged,
    this.errorText,
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

    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      maxLines: widget.maxLines,
      obscureText: canObscure && _obscureText,
      errorText: widget.errorText,
      onChanged: widget.onChanged,
      suffixIcon: canObscure
          ? IconButton(
              icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscureText = !_obscureText),
            )
          : null,
    );
  }
}
