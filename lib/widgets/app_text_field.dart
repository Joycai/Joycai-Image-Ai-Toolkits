import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// A single-line or multi-line text input with the app's input styling: a
/// hairline box on the surface, an accent border and glow ring when focused.
///
/// Replaces reaching for [TextField]/[TextFormField] directly, which is how
/// every input field in the app ended up with its own border style — some
/// outlined, some underlined, none sharing a fill colour.
///
/// **This was a filled field until the design spec landed.** The fill was tied
/// to [AppSegmentedControl]'s track tone so that a screen mixing input and
/// selection controls read as one system, which was sound — but it only ever
/// governed this widget, and this widget only ever had one caller
/// (`api_key_field.dart`). The ~40 bare `TextField`s that make up the rest of
/// the app's inputs were rendering Material's outlined default the whole time.
/// So the app was already mostly outlined, and the spec's outlined field is
/// what the `inputDecorationTheme` in [buildAppTheme] now gives all of them.
/// The shape here matches that theme; what this widget adds on top is the glow
/// ring, which [InputDecoration] cannot draw because it owns only the border.
class AppTextField extends StatefulWidget {
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
  State<AppTextField> createState() => _AppTextFieldState();
}

/// Thickness of the focus ring, and so also the inset this widget always
/// reserves for it.
const double _ringWidth = 3;

class _AppTextFieldState extends State<AppTextField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // An obscured field showing more than one line makes no sense — an
    // obscured newline can't be told apart from an obscured character — so
    // this pins it to one regardless of what the caller passed.
    final effectiveMaxLines = widget.obscureText ? 1 : widget.maxLines;

    // Shape and borders come from the ambient inputDecorationTheme; only the
    // content slots are named here, so this field and the bare TextFields
    // around the app cannot drift apart again.
    final decoration = InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      errorText: widget.errorText,
      prefixIcon: widget.prefixIcon,
      suffixIcon: widget.suffixIcon,
    );

    final Widget field = widget.validator != null
        ? TextFormField(
            controller: widget.controller,
            obscureText: widget.obscureText,
            maxLines: effectiveMaxLines,
            minLines: widget.minLines,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            validator: widget.validator,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: decoration,
          )
        : TextField(
            controller: widget.controller,
            obscureText: widget.obscureText,
            maxLines: effectiveMaxLines,
            minLines: widget.minLines,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: decoration,
          );

    // The spec's focus treatment is the accent border (which the decoration
    // theme draws) *plus* a 3px wash of the same accent outside it. Only the
    // border is an InputDecoration's to draw, so the ring is this wrapper.
    //
    // A padded box rather than a `BoxShadow`, which is the obvious reading and
    // is wrong here: a shadow is painted as a filled rounded rect behind the
    // container and is only hidden in the middle by the container's own
    // background — and this field has none, since the spec's input is outlined
    // rather than filled. The wash showed straight through the field.
    //
    // The padding is unconditional and only the colour animates, so gaining
    // focus does not nudge everything around the field by three pixels.
    //
    // `Focus` here is an ancestor of the field's own focus node rather than a
    // replacement for it: `hasFocus` on a parent node is true whenever a
    // descendant holds focus, so this needs no FocusNode of its own and does
    // not interfere with one the caller's controller may already drive.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) {
        if (value != _focused) setState(() => _focused = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(_ringWidth),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.control + _ringWidth),
          color: _focused ? colorScheme.accentRing : Colors.transparent,
        ),
        child: field,
      ),
    );
  }
}
