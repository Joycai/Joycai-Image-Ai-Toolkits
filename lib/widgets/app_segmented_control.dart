import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

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

/// How an [AppSegmentedControl] marks the chosen option.
enum AppSegmentStyle {
  /// Accent tint and outline. Reads as "on" against the track, which suits a
  /// control whose options are settings — streaming on/off, a filter.
  tinted,

  /// The chosen option lifts out of the track on a plain surface, the way a
  /// physical switch would. For a control that picks *which view you are in*
  /// rather than a value: the accent is then free to mean "selected" inside
  /// that view instead of being spent on the navigation.
  raised,
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

  /// Draw each option as its [AppSegment.icon] alone, with the label as its
  /// tooltip. For a toolbar on a phone, where the labelled track would take
  /// the whole row — the option is never left unexplained, only unlabelled.
  ///
  /// Segments without an icon keep their label, so a mixed track degrades
  /// rather than losing options.
  final bool iconOnly;

  /// How the chosen option is marked.
  final AppSegmentStyle style;

  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expand = false,
    this.compact = false,
    this.iconOnly = false,
    this.style = AppSegmentStyle.tinted,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // A tone above every surface the app puts this on, so the track is
        // visible whether it lands on a card or on the canvas.
        color: colorScheme.surfaceContainerHighest,
        // One step out from the chips it holds, so the gap between the two
        // curves stays even around the selected option's corners.
        borderRadius: BorderRadius.circular(AppRadius.md),
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
    final raised = style == AppSegmentStyle.raised;

    final Color color;
    if (!segment.enabled) {
      color = colorScheme.onSurface.withValues(alpha: AppAlpha.disabled);
    } else if (!selected) {
      color = colorScheme.onSurfaceVariant;
    } else {
      // Raised spends no accent on the label: the lift already says which one
      // is chosen, and the accent is needed for state *inside* the view.
      //
      // Tinted takes `onAccentTint`, not `primary`. The label is sitting on a
      // wash of primary, and primary on its own tint is the same tone twice —
      // legible in light mode by luck, and washed out in dark, where primary
      // is already a pale tone 80.
      color = raised ? colorScheme.onSurface : colorScheme.onAccentTint;
    }

    final bareIcon = iconOnly && segment.icon != null;

    final Widget chip = InkWell(
      onTap: selected || !segment.enabled ? null : () => onChanged(segment.value),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 7 : 11,
        ),
        decoration: !selected
            ? null
            : raised
                ? BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  )
                : BoxDecoration(
                    color: colorScheme.accentTint,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    // The spec's selection ring is markedly quieter than the
                    // 0.6 this used to draw — at that strength the border was
                    // competing with the label inside it for the eye.
                    border: Border.all(color: colorScheme.accentRing),
                  ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (segment.icon != null) ...[
              Icon(segment.icon, size: compact ? 14 : 17, color: color),
              if (!bareIcon) const SizedBox(width: 7),
            ],
            if (!bareIcon)
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (compact
                          ? Theme.of(context).textTheme.labelMedium
                          : Theme.of(context).textTheme.bodySmall)
                      ?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return bareIcon ? Tooltip(message: segment.label, child: chip) : chip;
  }
}
