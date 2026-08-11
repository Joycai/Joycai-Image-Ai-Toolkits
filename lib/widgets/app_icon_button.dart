import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// An icon action in a box of its own.
///
/// For icons that sit on a bare canvas or in a header, next to a segmented
/// control or a filled button rather than inside a list row. A bare icon out
/// there has no edge and reads as decoration; the outline says it is a target,
/// and squares it up with the controls beside it.
///
/// Not for icons inside rows, cards or app bars — a box around every one of
/// those is noise. Use a plain [IconButton] there.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Tints the icon and, when [selected], the box — for destructive actions and
  /// for buttons that report a state.
  final Color? color;

  /// Fills the box with [color] (or the primary) at a low alpha, for a button
  /// whose action is currently on.
  final bool selected;

  /// Both sides of the square.
  ///
  /// Two pixels under a labelled button rather than equal to it. The design
  /// spec sets them apart deliberately — a bare glyph with no word beside it
  /// should not carry the same visual weight as a stated verb — and at this
  /// difference the two still read as one row.
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.size = AppSize.iconButton,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = color ?? colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        // Half the box, per the spec's 16-in-32. The old 0.47 predates the box
        // being 32 and came out a pixel light once it shrank.
        icon: Icon(icon, size: size * 0.5),
        color: selected ? accent : color,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          // `color` when the caller named one — a destructive action's box
          // should wash in its own red, not in the accent.
          backgroundColor: selected ? accent.withValues(alpha: AppAlpha.tint) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
            side: BorderSide(
              color: selected ? accent.withValues(alpha: AppAlpha.ring) : colorScheme.outlineVariant,
            ),
          ),
        ),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}
