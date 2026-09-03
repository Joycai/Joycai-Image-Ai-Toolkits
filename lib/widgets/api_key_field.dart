import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

import 'app_text_field.dart';

/// A secret-entry field: obscured by default with a reveal toggle, for API
/// keys and other single-line credentials.
///
/// Built on [AppTextField] so it picks up the app's input styling; this
/// widget only adds the obscure/reveal behaviour on top.
class ApiKeyField extends StatefulWidget {
  final TextEditingController controller;

  /// Floating label, or null for a field whose caption is drawn above it by
  /// the caller (the `15a` form style).
  final String? label;
  final int maxLines;
  final Function(String) onChanged;

  /// Validation message shown under the field, which also turns its border
  /// and label red — the "this provider needs a key" state.
  final String? errorText;

  /// Placeholder shown while the field is empty. Used by the local-runtime
  /// providers, whose key is optional and whose field would otherwise look
  /// like something the user forgot to fill in.
  final String? hint;

  const ApiKeyField({
    super.key,
    required this.controller,
    this.label,
    this.maxLines = 1,
    required this.onChanged,
    this.errorText,
    this.hint,
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
      hint: widget.hint,
      maxLines: widget.maxLines,
      obscureText: canObscure && _obscureText,
      errorText: widget.errorText,
      onChanged: widget.onChanged,
      suffixIcon: canObscure
          ? IconButton(
              icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
              // Sized to the field, not Material's 48: an IconButton's own
              // minimum would otherwise hold this one input taller than the
              // form around it.
              iconSize: AppSize.iconLg,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              onPressed: () => setState(() => _obscureText = !_obscureText),
            )
          : null,
    );
  }
}
