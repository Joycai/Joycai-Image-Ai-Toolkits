import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// A single-line or multi-line text input with the app's input styling:
/// filled, borderless until focused, [appButtonRadius] corners.
///
/// Replaces reaching for [TextField]/[TextFormField] directly, which is how
/// every input field in the app ended up with its own border style — some
/// outlined, some underlined, none sharing a fill colour.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  /// Switches the field to [TextFormField] and wires this in — pass this
  /// only inside a [Form] with a [GlobalKey<FormState>], the same
  /// requirement [TextFormField] itself has.
  final String? Function(String?)? validator;

  final Widget? prefixIcon;
  final Widget? suffixIcon;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.keyboardType,
    this.onChanged,
    this.validator,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // An obscured field showing more than one line makes no sense — an
    // obscured newline can't be told apart from an obscured character — so
    // this pins it to one regardless of what the caller passed.
    final effectiveMaxLines = obscureText ? 1 : maxLines;

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(appButtonRadius),
      borderSide: BorderSide.none,
    );

    final decoration = InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      // Same tone AppSegmentedControl's track sits on, so a screen mixing
      // input and selection controls reads as one system rather than two.
      fillColor: colorScheme.surfaceContainerHighest,
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    );

    if (validator != null) {
      return TextFormField(
        controller: controller,
        obscureText: obscureText,
        maxLines: effectiveMaxLines,
        minLines: minLines,
        enabled: enabled,
        keyboardType: keyboardType,
        onChanged: onChanged,
        validator: validator,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: decoration,
      );
    }

    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: effectiveMaxLines,
      minLines: minLines,
      enabled: enabled,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: decoration,
    );
  }
}
