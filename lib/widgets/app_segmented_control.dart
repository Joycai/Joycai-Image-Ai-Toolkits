import 'package:flutter/material.dart';

/// One choice in an [AppSegmentedControl].
class AppSegment<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// A choice that exists but cannot be taken yet — shown, so the user knows
  /// the mode is there, and why the one they want is missing.
  final bool enabled;

  const AppSegment({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });
}

/// A single-choice control: a track holding its options, with the chosen one
/// filled in.
///
/// Replaces Material's [SegmentedButton], which draws the same choice as a pill
/// of hairline-divided buttons — at a glance the selection reads as "the button
/// that happens to be tinted" rather than as a position along a track. The
/// track also gives the control an edge of its own, which matters where these
/// sit on a bare canvas next to nothing else.
class AppSegmentedControl<T> extends StatelessWidget {
  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Split the width evenly between the options rather than letting each take
  /// only what its label needs. For controls that own their row.
  final bool expand;

  /// Tighter type and padding, for controls tucked into a toolbar.
  final bool compact;

  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // A tone above every surface the app puts this on, so the track is
        // visible whether it lands on a card or on the canvas.
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final segment in segments)
            if (expand)
              Expanded(child: _buildSegment(context, colorScheme, segment))
            else
              _buildSegment(context, colorScheme, segment),
        ],
      ),
    );
  }

  Widget _buildSegment(BuildContext context, ColorScheme colorScheme, AppSegment<T> segment) {
    final selected = segment.value == value;
    final Color color;
    if (!segment.enabled) {
      color = colorScheme.onSurface.withValues(alpha: 0.38);
    } else {
      color = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    }

    return InkWell(
      onTap: selected || !segment.enabled ? null : () => onChanged(segment.value),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 7 : 11,
        ),
        decoration: selected
            ? BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.6)),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (segment.icon != null) ...[
              Icon(segment.icon, size: compact ? 14 : 17, color: color),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
