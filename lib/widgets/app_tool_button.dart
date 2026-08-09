import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// A quiet icon+label action for a toolbar: no fill of its own until the
/// pointer is on it.
///
/// These sit in the workbench's top bar next to the image/video segmented
/// control, and the two are not peers — the segmented control says which mode
/// the workbench is in, while these open a tool. Giving each tool a box or a
/// fill puts them at the same weight as that control and the row turns into
/// six things competing; leaving them bare until hover keeps the row legible
/// and still tells the user they are targets the moment the pointer arrives.
///
/// The rest state is deliberately neutral rather than accented: with the
/// greys already free of the seed hue (see [buildAppColorScheme]), reserving
/// the accent for [active] makes "this tool is open" readable at a glance.
class AppToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// The tool this button opens is currently showing — takes the accent, so
  /// the open tool is identifiable without reading the row.
  final bool active;

  /// Drops the label and keeps the icon, for a toolbar too narrow to spell
  /// every tool out. [label] is still required: it becomes the tooltip, so
  /// the button never becomes an unexplained glyph.
  final bool showLabel;

  const AppToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = active ? colorScheme.primary : colorScheme.onSurfaceVariant;

    final style = TextButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: active ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      // Neutral, not the accent Material would tint this with: an accented
      // hover on every tool would read as several half-selected buttons.
      overlayColor: colorScheme.onSurface,
      textStyle: Theme.of(context).textTheme.labelLarge,
      padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 0),
      minimumSize: Size(showLabel ? 0 : appButtonMinHeight, appButtonMinHeight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appButtonRadius)),
      visualDensity: VisualDensity.standard,
    );

    if (!showLabel) {
      return Tooltip(
        message: label,
        child: TextButton(
          onPressed: onPressed,
          style: style,
          child: Icon(icon, size: 20),
        ),
      );
    }

    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: style,
    );
  }
}
