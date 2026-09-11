import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'app_field_size.dart';

/// A "type to narrow this list" field: search glyph, hint, and a clear button
/// that appears once there is something to clear.
///
/// Six of these existed, one per list that needed filtering, and no two agreed
/// — corner radii of 8, 10, 12 and 18; glyphs at 14, 16, 18 and 20; fills at
/// three different alphas of the same tone; and five separate pieces of state
/// whose only job was to know whether the clear button should be on screen.
///
/// **The fill is gone.** These were filled boxes when the rest of the app's
/// inputs were too; the design spec draws a search field as an outlined one,
/// and [buildAppTheme]'s `inputDecorationTheme` now gives that to every bare
/// `TextField`. This widget adds the two things that make a field a *search*
/// field and inherits everything else, so it cannot drift from the inputs
/// beside it again.
///
/// **Pinned to [height].** It used to take no height and fill its slot, but a
/// decorator draws its outline around its content, not around the slot: the
/// outline came out 32 under a scope whose icon constraints happened to be 32
/// and 19 under one whose were not. [compact] governs only the glyph and the
/// type.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
    this.focusNode,
    this.autofocus = false,
    this.compact = false,
    this.height = AppSize.control,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Runs after the field has been emptied, for call sites whose list is
  /// driven by something other than [onChanged] — a state object holding the
  /// query, say, which has to be told separately.
  ///
  /// [onChanged] fires on clear as well, so a call site that already handles
  /// its query there needs nothing here.
  final VoidCallback? onCleared;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Tighter glyph and type, for a field sharing a strip with icon buttons —
  /// the log console's filter, which lives in a 40px bar.
  final bool compact;

  /// The box's height, outline included. [AppSize.control] on every pointer
  /// surface; a touch-only slot that is deliberately taller passes its own.
  final double height;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  @override
  void initState() {
    super.initState();
    // The clear button's visibility is the field's own business. Every call
    // site used to carry a `_searchQuery` string or an `isEmpty` check purely
    // to rebuild for it, which meant six chances to forget.
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    // The controller belongs to the caller, so only the listener is ours to
    // take back.
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onCleared?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final style = widget.compact ? textTheme.bodySmall : textTheme.bodyMedium;
    final glyph = widget.compact ? 14.0 : AppSize.iconMd;
    final clearBox = math.min(AppSize.compact, widget.height);

    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: style,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: style?.copyWith(color: colorScheme.outline),
        isDense: true,
        constraints: BoxConstraints.tightFor(height: widget.height),
        // Vertical only: the glyph boxes are the horizontal inset. Border,
        // radius, fill and focus treatment all come from the theme.
        contentPadding: EdgeInsets.symmetric(
          vertical: pinnedFieldInset(context, style, widget.height),
        ),
        prefixIcon: Icon(Icons.search, size: glyph, color: colorScheme.outline),
        // Zero minimum heights, so no icon box can set the field's height.
        prefixIconConstraints: const BoxConstraints(minWidth: AppSize.control, minHeight: 0),
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, size: glyph, color: colorScheme.onSurfaceVariant),
                onPressed: _clear,
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                padding: EdgeInsets.zero,
                // No taller than the field, and without the padded 48px tap
                // target touch platforms would otherwise wrap it in.
                constraints: BoxConstraints.tightFor(width: clearBox, height: clearBox),
                style: IconButton.styleFrom(
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: AppSize.control, minHeight: 0),
      ),
    );
  }
}
