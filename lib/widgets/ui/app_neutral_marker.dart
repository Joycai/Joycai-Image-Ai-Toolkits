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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: AppSpace.s4, right: AppSpace.s6, top: 1, bottom: 1),
      decoration: BoxDecoration(
        color: scheme.outlineVariant,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 2),
          Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
