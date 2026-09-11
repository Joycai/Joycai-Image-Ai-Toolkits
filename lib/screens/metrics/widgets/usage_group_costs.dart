import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/pricing_group.dart';
import 'usage_chrome.dart';
import 'usage_palette.dart';
import 'usage_stats.dart';

/// Cost per fee group for the range, as one card of bars (`D2` ③).
///
/// Each bar is as long as the group's share of the range's total spend, not
/// its share of the largest group: scaled to the biggest, the top group would
/// fill the track every time and the bar would stop saying anything. The
/// length is then divided into what the money went on — input, cache, output
/// in the token identity colours, and request-billed jobs as a neutral
/// remainder.
class UsageGroupCosts extends StatelessWidget {
  final UsageStats stats;
  final List<PricingGroup> groups;

  const UsageGroupCosts({super.key, required this.stats, required this.groups});

  /// Column widths of the desktop row, as drawn.
  static const double _nameWidth = 150;
  static const double _costWidth = 90;
  static const double _requestsWidth = 110;
  static const double _gap = 12;
  static const double _rowGap = AppSpace.s10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final byId = {for (final g in groups) g.id: g};

    // Groups deleted since their usage was recorded keep their cost in the
    // stats but have no name left to show, so they only survive in the total.
    final entries = stats.groupCosts.entries
        .where((e) => byId.containsKey(e.key))
        .map((e) => (group: byId[e.key]!, cost: e.value, usage: stats.groupUsage[e.key]))
        .toList()
      ..sort((a, b) => b.cost.compareTo(a.cost));

    if (entries.isEmpty) return const SizedBox.shrink();

    final wide = Responsive.isDesktop(context);

    return UsagePanel(
      padding: const EdgeInsets.all(AppSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          UsageCaption(l10n.usageByGroup),
          for (final entry in entries) ...[
            const SizedBox(height: _rowGap),
            wide
                ? _buildWideRow(context, l10n, entry.group, entry.cost, entry.usage)
                : _buildNarrowRow(context, l10n, entry.group, entry.cost, entry.usage),
          ],
        ],
      ),
    );
  }

  double _shareOf(double cost) =>
      stats.totalCost > 0 ? (cost / stats.totalCost).clamp(0.0, 1.0) : 0.0;

  Widget _buildWideRow(
    BuildContext context,
    AppLocalizations l10n,
    PricingGroup group,
    double cost,
    GroupUsage? usage,
  ) {
    return Row(
      children: [
        SizedBox(width: _nameWidth, child: _name(context, group)),
        const SizedBox(width: _gap),
        Expanded(child: _GroupBar(share: _shareOf(cost), usage: usage)),
        const SizedBox(width: _gap),
        SizedBox(width: _costWidth, child: _cost(context, cost, TextAlign.end)),
        const SizedBox(width: _gap),
        SizedBox(
          width: _requestsWidth,
          child: usage == null ? null : _requests(context, l10n, usage, TextAlign.end),
        ),
      ],
    );
  }

  Widget _buildNarrowRow(
    BuildContext context,
    AppLocalizations l10n,
    PricingGroup group,
    double cost,
    GroupUsage? usage,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: _name(context, group)),
            const SizedBox(width: AppSpace.s10),
            _cost(context, cost, TextAlign.end),
            if (usage != null) ...[
              const SizedBox(width: AppSpace.s10),
              _requests(context, l10n, usage, TextAlign.end),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.s6),
        _GroupBar(share: _shareOf(cost), usage: usage),
      ],
    );
  }

  Widget _name(BuildContext context, PricingGroup group) {
    return Text(
      group.name,
      style: Theme.of(context).textTheme.labelMedium,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _cost(BuildContext context, double cost, TextAlign align) {
    return Text(
      '\$${cost.toStringAsFixed(4)}',
      textAlign: align,
      maxLines: 1,
      style: Theme.of(context).textTheme.bodySmall?.mono.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
    );
  }

  Widget _requests(BuildContext context, AppLocalizations l10n, GroupUsage usage, TextAlign align) {
    return Text(
      '${NumberFormat.decimalPattern().format(usage.requestCount)} ${l10n.requests}',
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// The 8px bar: the group's share of the total, split by what it was spent on.
///
/// The share itself is a [LinearProgressIndicator] — the bar's length is a
/// progress-shaped fact, and that is what reads it out to assistive tech. The
/// segments are painted over exactly that length. Without a breakdown (stats
/// built from a checkpoint) the bar stays one neutral colour.
class _GroupBar extends StatelessWidget {
  const _GroupBar({required this.share, required this.usage});

  final double share;
  final GroupUsage? usage;

  static const double _height = 8;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final neutral = colorScheme.outline;
    final usage = this.usage;

    final segments = <(double, Color)>[
      if (usage != null && usage.totalCost > 0) ...[
        (usage.inputCost, UsageToken.input.colorOf(context)),
        (usage.cacheCost, UsageToken.cache.colorOf(context)),
        (usage.outputCost, UsageToken.output.colorOf(context)),
        (usage.requestCost, neutral),
      ],
    ].where((s) => s.$1 > 0).toList();

    String money(double v) => '\$${v.toStringAsFixed(4)}';
    final tooltip = [
      '${(share * 100).toStringAsFixed(1)}%',
      if (usage != null && usage.totalCost > 0) ...[
        if (usage.inputCost > 0) '${l10n.inputTokens}: ${money(usage.inputCost)}',
        if (usage.cacheCost > 0) '${l10n.cachedInputTokens}: ${money(usage.cacheCost)}',
        if (usage.outputCost > 0) '${l10n.outputTokens}: ${money(usage.outputCost)}',
        if (usage.requestCost > 0) '${l10n.requests}: ${money(usage.requestCost)}',
      ],
    ].join('\n');

    return Tooltip(
      message: tooltip,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: SizedBox(
          height: _height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LinearProgressIndicator(
                value: share,
                minHeight: _height,
                color: neutral,
                backgroundColor: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.zero,
              ),
              if (segments.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: share,
                    heightFactor: 1,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (part, color) in segments)
                          Expanded(
                            flex: (part / usage!.totalCost * 1000).round().clamp(1, 1000),
                            child: ColoredBox(color: color),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
