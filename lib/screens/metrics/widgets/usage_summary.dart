import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'usage_chrome.dart';
import 'usage_stats.dart';
import 'usage_token_charts.dart';

/// Range totals, a token composition chart and a prompt-cache gauge.
/// Layout follows the available card width, including iPad split views.
class UsageSummary extends StatelessWidget {
  const UsageSummary({
    super.key,
    required this.stats,
    required this.rangeLabel,
    this.compact = false,
  });

  final UsageStats stats;
  final String rangeLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return UsagePanel(
      padding: const EdgeInsets.all(AppSpace.s16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final charts = UsageTokenCharts(stats: stats);
          if (!compact && constraints.maxWidth >= 1100) {
            return Row(
              children: [
                SizedBox(
                  width: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UsageCaption(l10n.estimatedCost),
                      const SizedBox(height: AppSpace.s6),
                      _costFigure(context),
                      const SizedBox(height: AppSpace.s6),
                      _metaLine(context, l10n),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.s28),
                Expanded(child: charts),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _headlineRow(context, l10n),
              const SizedBox(height: AppSpace.s16),
              charts,
            ],
          );
        },
      ),
    );
  }

  Widget _costFigure(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        '\$${stats.totalCost.toStringAsFixed(4)}',
        // Ink, never green: a cost is not a success, only a number.
        style: Theme.of(context).textTheme.headlineLarge?.mono.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          height: AppType.displayHeight,
        ),
      ),
    );
  }

  TextStyle? _metaStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.labelSmall?.mono.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  String _requestsText(AppLocalizations l10n) =>
      '${_fmt(stats.totalRequestCount)} ${l10n.requests}';

  /// The period and the request count on one line. Two texts rather than one
  /// joined string: each is a fact of its own, and gives way on its own.
  Widget _metaLine(BuildContext context, AppLocalizations l10n) {
    final style = _metaStyle(context);
    return Row(
      children: [
        Flexible(
          child: Text(rangeLabel, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Text(' · ', style: style),
        Flexible(
          child: Text(
            _requestsText(l10n),
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Compact forms: the caption and the cost on the left, the period and the
  /// request count stacked on the right.
  Widget _headlineRow(BuildContext context, AppLocalizations l10n) {
    final style = _metaStyle(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              UsageCaption(l10n.estimatedCost),
              const SizedBox(height: AppSpace.s6),
              _costFigure(context),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rangeLabel, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(_requestsText(l10n), style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(int value) => NumberFormat.decimalPattern().format(value);
}
