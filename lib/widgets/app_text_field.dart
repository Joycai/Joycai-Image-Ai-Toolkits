import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'app_field_size.dart';

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

/// Thickness of the focus ring, which is drawn outside the field's box.
const double _ringWidth = 3;

class _AppTextFieldState extends State<AppTextField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = theme.textTheme.bodyMedium;
    // An obscured field showing more than one line makes no sense — an
    // obscured newline can't be told apart from an obscured character — so
    // this pins it to one regardless of what the caller passed.
    final effectiveMaxLines = widget.obscureText ? 1 : widget.maxLines;

    // A single-line field with its caption outside it is the 32px control.
    // A floating label or an error line lives inside the decorator's own box,
    // and `constraints` bounds that whole box, so those fields keep the
    // theme's height rather than being clipped.
    final bool pinned = widget.label == null &&
        widget.errorText == null &&
        effectiveMaxLines == 1 &&
        (widget.minLines ?? 1) <= 1;
    EdgeInsets? padding;
    if (pinned) {
      final themed = (theme.inputDecorationTheme.contentPadding ?? EdgeInsets.zero)
          .resolve(Directionality.of(context));
      final vertical = pinnedFieldInset(context, style, AppSize.control);
      padding = EdgeInsets.fromLTRB(themed.left, vertical, themed.right, vertical);
    }
    const iconBox = BoxConstraints(minWidth: AppSize.control, minHeight: 0);

    // Shape and borders come from the ambient inputDecorationTheme; only the
    // content slots — and, when pinned, the height — are named here, so this
    // field and the bare TextFields around the app cannot drift apart again.
    final decoration = InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      errorText: widget.errorText,
      prefixIcon: widget.prefixIcon,
      suffixIcon: widget.suffixIcon,
      isDense: pinned ? true : null,
      constraints: pinned ? const BoxConstraints.tightFor(height: AppSize.control) : null,
      contentPadding: padding,
      prefixIconConstraints: pinned ? iconBox : null,
      suffixIconConstraints: pinned ? iconBox : null,
    );
    final TextAlignVertical? align = pinned ? TextAlignVertical.center : null;

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
            style: style,
            textAlignVertical: align,
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
            style: style,
            textAlignVertical: align,
            decoration: decoration,
          );

    // The spec's focus treatment is the accent border (which the decoration
    // theme draws) *plus* a 3px wash of the same accent outside it. Only the
    // border is an InputDecoration's to draw, so the ring is this wrapper.
    //
    // It has to be an actual `Border`, and both of the obvious alternatives
    // are the same bug twice. A `BoxShadow` paints a filled rounded rect
    // behind the container, hidden in the middle only by the container's own
    // background — and this field has none, since the spec's input is
    // outlined rather than filled, so the wash showed straight through it. A
    // padded box with `color:` set does *exactly* the same thing: `color` on
    // a BoxDecoration fills the whole rounded rect, and the transparent field
    // sitting in the middle of it let 32% of the accent through. That shipped,
    // and it is what every focused field in the component gallery was tinted
    // with. A border paints the edge only, which is all this ever wanted.
    //
    // The ring is laid over the field, 3px outside its box, and takes no
    // layout. It used to be a Container around the field, which reserved the
    // 3px on every side whether focused or not — so the field sat 3px inset
    // from the caption above it and from every neighbour in its row.
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          field,
          Positioned(
            left: -_ringWidth,
            top: -_ringWidth,
            right: -_ringWidth,
            bottom: -_ringWidth,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: AppMotion.durationOf(context, AppMotion.hover),
                curve: AppMotion.enter,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.control + _ringWidth),
                  border: Border.all(
                    color: _focused ? colorScheme.accentRing : Colors.transparent,
                    width: _ringWidth,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gives every input under [child] the filled skin `D2` draws: a box a step
/// off the panel it sits on, rather than the app-wide outlined default.
///
/// Scoped rather than themed globally, and the reason is that the two are both
/// right in their own places. An input on a toolbar or a bare canvas — the
/// workbench's, the gallery's — wants the outline: its neighbours are buttons
/// and chips, and a fill there reads as a second surface nobody asked for. An
/// input *in a form*, among a column of sibling fields, wants the fill: it is
/// what tells the field apart from the panel behind it when there is nothing
/// else in the row to do that. `D2`'s frames are all the second kind, which is
/// why the models screen and its dialogs opt in and nothing else does.
///
/// Reach for this per screen as a frame is aligned, not once for the app.
/// Flipping the theme default instead is what put a fill under half the
/// workbench in a change that was only ever about the model editor.
class FilledFieldScope extends StatelessWidget {
  const FilledFieldScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          // The ramp's step, not a tint of the accent — the grey that *was*
          // accent-tied is what got the fill removed from this widget in the
          // first place. `surfaceContainerLowest` is the same reading
          // `AppCard`'s outlined form settled on: a hair above the panel in
          // light, and in dark a step below it, so a field reads as a well
          // rather than a raised chip. Which is the right physics for a place
          // you type into.
          fillColor: theme.colorScheme.surfaceContainerLowest,
          // `D2` draws these forms' fields at 40, glyph or no glyph. Material
          // gives a prefix or suffix icon a 48px box, and that box — not the
          // text — was setting every iconed field in the editors eight pixels
          // taller than the dropdowns and the fields without one.
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
          suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
        ),
      ),
      child: child,
    );
  }
}
