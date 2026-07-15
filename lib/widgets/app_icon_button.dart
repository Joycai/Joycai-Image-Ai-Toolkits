import 'package:flutter/material.dart';

import '../core/app_theme.dart';

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

  /// Both sides of the square. Defaults to the height of a filled button so the
  /// two line up in a header.
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.size = appButtonMinHeight,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = color ?? colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        icon: Icon(icon, size: size * 0.47),
        color: selected ? accent : color,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: selected ? accent.withValues(alpha: 0.14) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(appButtonRadius),
            side: BorderSide(
              color: selected ? accent.withValues(alpha: 0.6) : colorScheme.outline.withValues(alpha: 0.45),
            ),
          ),
        ),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}
