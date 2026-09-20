import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

/// A small marker stating a fact about the row it sits on — `A3e`'s 「分析」 on
/// a preset whose result is an answer rather than a prompt.
///
/// Neutral on purpose, and not to follow the seed: it names a property, not a
/// status and not a selection, so it takes the hairline ground and the
/// secondary ink whatever the accent is. Only the minority case wears one;
/// the default says nothing.
class AppNeutralMarker extends StatelessWidget {
  const AppNeutralMarker({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// Vertical space the marker adds around its single line of type. Public
  /// for the reason `ModelTagChip.chromeHeight` is: a fixed-extent list has
  /// to know how tall a row carrying one can be before it lays one out.
  static const double chromeHeight = 2 * _vPad;

  static const double _vPad = 1;

  /// Smaller than the label's line, so the line — not the glyph — sets the
  /// marker's height and [chromeHeight] stays the whole of its chrome.
  static const double _iconSize = 12;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(
        left: AppSpace.s4,
        right: AppSpace.s6,
        top: _vPad,
        bottom: _vPad,
      ),
      decoration: BoxDecoration(
        // The track ground, not the hairline: a hairline is drawn to be
        // barely there, and the secondary ink on it falls short of AA in light.
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _iconSize, color: scheme.onSurfaceVariant),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
