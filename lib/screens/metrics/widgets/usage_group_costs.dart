import 'package:flutter/material.dart';

import '../../../core/fee_group_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/pricing_group.dart';
import '../../../widgets/panel_resizer.dart';
import 'usage_stats.dart';

/// Cost per fee group for the range, as cards on the canvas.
///
/// Each card carries a bar showing the group's share of the range's total
/// spend. The costs alone already say which group is expensive; the bars say
/// by how much, which is the question anyone reading a list of four numbers is
/// actually asking. They are drawn against the total rather than against the
/// largest group, so a bar that fills half the track means half the money —
/// scaling to the biggest would make the top group full-width every time and
/// tell you nothing.
class UsageGroupCosts extends StatelessWidget {
  final UsageStats stats;
  final List<PricingGroup> groups;

  const UsageGroupCosts({super.key, required this.stats, required this.groups});

  /// Cards below this width start truncating group names, so the row gives up
  /// a column instead.
  static const double _minCardWidth = 220;
  static const double _spacing = 8;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final byId = {for (final g in groups) g.id: g};

    // Groups deleted since their usage was recorded keep their cost in the
    // stats but have no name left to show, so they only survive in the total.
    final entries = stats.groupCosts.entries
        .where((e) => byId.containsKey(e.key))
        .map((e) => (group: byId[e.key]!, cost: e.value))
        .toList()
      ..sort((a, b) => b.cost.compareTo(a.cost));

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.usageByGroup,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            // Capped at four: past that the cards are narrower than the names
            // they hold, and a fifth column buys nothing a second row doesn't.
            final columns = ((constraints.maxWidth + _spacing) / (_minCardWidth + _spacing))
                .floor()
                .clamp(1, 4);
            final cardWidth =
                (constraints.maxWidth - _spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: _spacing,
              runSpacing: _spacing,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: cardWidth,
                    child: _buildCard(context, entry.group, entry.cost),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, PricingGroup group, double cost) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = feeGroupAccent(group.id);
    final share = stats.totalCost > 0 ? (cost / stats.totalCost).clamp(0.0, 1.0) : 0.0;

    return PanelCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '\$${cost.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Tooltip(
              message: '${(share * 100).toStringAsFixed(1)}%',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 5,
                  backgroundColor: colorScheme.onSurface.withAlpha(18),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
