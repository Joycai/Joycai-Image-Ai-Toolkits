import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// One choice in an [AppDropdown].
class AppDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// What the closed field shows when this is the choice, if not [label].
  /// The model editor's protocol field says 「自动」 in the menu and
  /// 「自动 · 当前解析为 X」 once chosen.
  final String? selectedLabel;

  /// Drawn in the outline colour, in the menu and the closed field both: a
  /// "none" row that is a real answer but not a thing.
  final bool muted;

  const AppDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.selectedLabel,
    this.muted = false,
  });
}

/// The spec's dropdown: a menu behind a field drawn exactly like every other
/// select-like control in the app.
///
/// For choosing one of a short, fixed option set — an aspect ratio, a
/// resolution, a sampling filter. A long or searchable list is
/// [SearchablePickerField]; a 2–4 way choice that should read as one control
/// rather than a menu is [AppSegmentedControl].
///
/// **Drawn as the same object as [SearchablePickerField].** `10a` gives every
/// select in the design one box — the input outline, the control radius, a
/// single downward chevron — and `16a`/`17b` put a dropdown directly under a
/// picker in the same card. The two used to be different heights, different
/// text sizes and different arrows: Material's `DropdownButtonFormField`
/// brings a filled triangle and a 24px-tall dense button, where the picker is
/// one line of `bodySmall` in the theme's insets. The border, radius and
/// horizontal insets here come from [ThemeData.inputDecorationTheme] like the
/// picker's do; the vertical inset is derived so the two land at the same
/// height (see [_verticalInset]).
///
/// Controlled, not a `FormField`: [value] is what the caller holds, every
/// build. `DropdownButtonFormField` owns its value and only re-syncs when
/// `initialValue` *changes* between builds, which is how a parameter row
/// switched to a new model while a write was still in flight came to display
/// a value the state did not hold.
class AppDropdown<T> extends StatefulWidget {
  final T? value;
  final List<AppDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;

  /// A floating Material label inside the box. Most call sites caption the
  /// field with an [AppLabelledField] above it instead and leave this null.
  final String? label;
  final String? hint;

  /// A glyph ahead of the value, the way the model and channel editors' text
  /// fields carry one. Drawn at the same size the channel editor's protocol
  /// field settled on, and it brings Material's 48px minimum with it — which
  /// is the height of the fields it sits among there.
  final IconData? prefixIcon;

  /// A line under the box, in the decoration's helper slot.
  final String? helperText;
  final int? helperMaxLines;

  /// Pin the box to this height instead of the theme's. For a toolbar whose
  /// every control is [AppSize.control] tall; the vertical inset is derived
  /// from it rather than the theme's.
  final double? height;

  final bool enabled;

  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.prefixIcon,
    this.helperText,
    this.helperMaxLines,
    this.height,
    this.enabled = true,
  });

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

/// The height Material's dense `DropdownButton` never goes under —
/// `_kDenseButtonHeight` in `dropdown.dart`, which is private. The button is
/// `max(scaled font size, max(icon size, this))` tall.
const double _denseButtonHeight = 24;

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  /// Handed to [InputDecorator], which draws the theme's `focusedBorder` and
  /// hover fill from them and otherwise assumes both are false. The same
  /// reason [SearchablePickerField] tracks its own: without them this was a
  /// field that tabbing onto looked the same as tabbing past.
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus != _focused) setState(() => _focused = _focusNode.hasFocus);
  }

  /// How tall the dense button inside will be, for [style] and [iconSize].
  double _buttonHeight(BuildContext context, TextStyle? style, double iconSize) {
    final scaler = MediaQuery.textScalerOf(context);
    return math.max(scaler.scale(style?.fontSize ?? 0), math.max(iconSize, _denseButtonHeight));
  }

  /// The vertical inset that makes this box the height of a
  /// [SearchablePickerField] drawn from the same theme.
  ///
  /// The picker's content is one line of [style]; this one's is a dense
  /// dropdown button, which is at least [_denseButtonHeight] tall however
  /// small its text. So the theme's inset is reduced by half the difference —
  /// measured from the actual font, since the user can swap the app onto one
  /// with different metrics — and never below zero, so a large text scale
  /// simply makes both fields grow together.
  double _verticalInset(BuildContext context, TextStyle? style, double themeInset, double iconSize) {
    final lineHeight = (TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout())
        .height;
    return math.max(0, themeInset - (_buttonHeight(context, style, iconSize) - lineHeight) / 2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final enabled = widget.enabled && widget.onChanged != null;

    // bodySmall, as the picker and the dense config panels these sit in.
    final valueStyle = textTheme.bodySmall?.copyWith(
      color: enabled ? colorScheme.onSurface : colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
    );
    final outline = enabled ? colorScheme.outline : colorScheme.outline.withValues(alpha: AppAlpha.disabled);

    final themeInset =
        theme.inputDecorationTheme.contentPadding?.resolve(Directionality.of(context)) ??
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final double vertical;
    if (widget.height != null) {
      // The box's own 1px border top and bottom comes out of the pinned height
      // before the button is centred in what is left.
      vertical = math.max(0, (widget.height! - 2 - _buttonHeight(context, valueStyle, AppSize.iconSm)) / 2);
    } else {
      vertical = _verticalInset(context, valueStyle, themeInset.top, AppSize.iconSm);
    }

    Text itemText(AppDropdownItem<T> item, String text) => Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: item.muted ? valueStyle?.copyWith(color: outline) : null,
        );

    final hasSelectedLabels = widget.items.any((i) => i.selectedLabel != null);

    Widget field = InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        // The hint is the button's to draw (below); naming it here too would
        // paint it twice.
        helperText: widget.helperText,
        helperMaxLines: widget.helperMaxLines,
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: AppSize.iconLg),
        enabled: enabled,
        contentPadding: EdgeInsets.fromLTRB(themeInset.left, vertical, themeInset.right, vertical),
      ),
      isFocused: _focused,
      isHovering: _hovered,
      // A hint counts as content, as it does for DropdownButtonFormField:
      // with nothing selected the label floats clear of it rather than
      // lying over the top.
      isEmpty: widget.value == null && widget.hint == null,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: widget.value,
          focusNode: _focusNode,
          isExpanded: true,
          isDense: true,
          // expand_more, not the filled triangle: the design draws one
          // downward chevron on every select-like field.
          icon: Icon(Icons.expand_more, color: outline),
          iconSize: AppSize.iconSm,
          style: valueStyle,
          hint: widget.hint == null
              ? null
              : Text(widget.hint!, style: valueStyle?.copyWith(color: outline), overflow: TextOverflow.ellipsis),
          // Only built when some item reads differently once chosen; the
          // builder has to answer for every item, so the rest repeat [label].
          selectedItemBuilder: hasSelectedLabels
              ? (context) => [
                    for (final item in widget.items)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: itemText(item, item.selectedLabel ?? item.label),
                      ),
                  ]
              : null,
          items: [
            for (final item in widget.items)
              DropdownMenuItem<T>(
                value: item.value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: AppSize.iconSm),
                      const SizedBox(width: 8),
                    ],
                    Flexible(child: itemText(item, item.label)),
                  ],
                ),
              ),
          ],
          onChanged: enabled ? widget.onChanged : null,
        ),
      ),
    );

    if (widget.height != null) field = SizedBox(height: widget.height, child: field);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: field,
    );
  }
}
