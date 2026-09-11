import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import 'usage_chrome.dart';
import 'usage_palette.dart';
import 'usage_stats.dart';

/// The hero card at the top of the usage view (`D2` ①).
///
/// Cost first and largest, because it is the number the screen exists to
/// answer, with the period and request count it is a total *of* beneath it.
/// Then the three token counts, each keyed by its identity colour, and the
/// cache hit rate — the one figure on the screen drawn in the accent.
///
/// Three forms of one card: a row on desktop; with [compact], a stacked card
/// with a 2×2 tile grid on a tablet, and a single column of rows on a phone.
class UsageSummary extends StatelessWidget {
  final UsageStats stats;

  /// The active range preset, named — "Last Week", not the dates it resolved
  /// to. Every number on this card is a total *over that range*, and a total
  /// with no period attached is not a fact. The resolved dates are spelled out
  /// beside the presets, where changing them is possible.
  final String rangeLabel;

  final bool compact;

  const UsageSummary({
    super.key,
    required this.stats,
    required this.rangeLabel,
    this.compact = false,
  });

  /// The card's inset and the gap between its three groups, as drawn.
  static const double _widePadding = 20;
  static const double _groupGap = AppSpace.s28;
  static const double _costWidth = 260;
  static const double _hitRateWidth = 150;
  static const double _tileGap = AppSpace.s10;

  @override
  Widget build(BuildContext context) {
    if (!compact) return _buildWide(context);
    return Responsive.isMobile(context) ? _buildPhone(context) : _buildTablet(context);
  }

  // --- Forms --------------------------------------------------------------

  Widget _buildWide(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return UsagePanel(
      padding: const EdgeInsets.all(_widePadding),
      // IntrinsicHeight so every tile takes the tallest one's height rather
      // than floating at its own.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _costWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(width: _groupGap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, token) in UsageToken.values.indexed) ...[
                    if (index > 0) const SizedBox(width: _tileGap),
                    Expanded(child: _tokenTile(context, l10n, token, showBar: true)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: _groupGap),
            SizedBox(
              width: _hitRateWidth,
              child: _hitRateTile(context, l10n, showBar: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTablet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return UsagePanel(
      padding: const EdgeInsets.all(AppSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headlineRow(context, l10n),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _tokenTile(context, l10n, UsageToken.input)),
                const SizedBox(width: _tileGap),
                Expanded(child: _tokenTile(context, l10n, UsageToken.cache)),
              ],
            ),
          ),
          const SizedBox(height: _tileGap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _tokenTile(context, l10n, UsageToken.output)),
                const SizedBox(width: _tileGap),
                Expanded(child: _hitRateTile(context, l10n)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhone(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final rate = stats.cacheHitRate;

    return UsagePanel(
      padding: const EdgeInsets.all(AppSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headlineRow(context, l10n),
          const SizedBox(height: 12),
          for (final token in UsageToken.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  UsageDot(token.colorOf(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      token.labelOf(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        _fmt(_tokenValue(token)),
                        style: textTheme.bodySmall?.mono.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Tooltip(
            message: l10n.cacheHitRateHint,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          l10n.cacheHitRate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: AppSpace.s4),
                      Icon(Icons.help_outline, size: AppSize.iconSm, color: colorScheme.outline),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _rateText(rate),
                  style: textTheme.bodySmall?.mono.copyWith(
                    fontWeight: FontWeight.w600,
                    color: rate == null ? colorScheme.outline : colorScheme.onAccentTint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Pieces -------------------------------------------------------------

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

  TextStyle? _metaStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.mono.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );

  String _requestsText(AppLocalizations l10n) => '${_fmt(stats.totalRequestCount)} ${l10n.requests}';

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
          child: Text(_requestsText(l10n), style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
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

  /// The column-ground tile the token counts and the hit rate share.
  Widget _tile(BuildContext context, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _tileLabel(BuildContext context, String label) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _tileFigure(BuildContext context, String text, {Color? color}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: Theme.of(context).textTheme.headlineMedium?.mono.copyWith(
              color: color ?? Theme.of(context).colorScheme.onSurface,
              height: AppType.displayHeight,
            ),
      ),
    );
  }

  /// A token count, keyed by its dot. On desktop a mini bar under it shows the
  /// count's share of all three.
  Widget _tokenTile(BuildContext context, AppLocalizations l10n, UsageToken token, {bool showBar = false}) {
    final color = token.colorOf(context);
    final all = stats.totalInput + stats.totalCache + stats.totalOutput;
    final value = _tokenValue(token);

    return _tile(context, [
      Row(
        children: [
          UsageDot(color),
          const SizedBox(width: AppSpace.s6),
          Expanded(child: _tileLabel(context, token.labelOf(l10n))),
        ],
      ),
      const SizedBox(height: AppSpace.s4),
      _tileFigure(context, _fmt(value)),
      if (showBar) ...[
        const SizedBox(height: AppSpace.s6),
        UsageShareBar(share: all == 0 ? 0 : value / all, color: color),
      ],
    ]);
  }

  /// The cached share of prompt tokens — the one figure here in the accent.
  Widget _hitRateTile(BuildContext context, AppLocalizations l10n, {bool showBar = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final rate = stats.cacheHitRate;

    return Tooltip(
      message: l10n.cacheHitRateHint,
      child: _tile(context, [
        Row(
          children: [
            Expanded(child: _tileLabel(context, l10n.cacheHitRate)),
            const SizedBox(width: AppSpace.s4),
            Icon(Icons.help_outline, size: AppSize.iconSm, color: colorScheme.outline),
          ],
        ),
        const SizedBox(height: AppSpace.s4),
        _tileFigure(
          context,
          _rateText(rate),
          color: rate == null ? colorScheme.outline : colorScheme.onAccentTint,
        ),
        if (showBar) ...[
          const SizedBox(height: AppSpace.s6),
          LinearProgressIndicator(
            value: rate ?? 0,
            minHeight: 4,
            color: colorScheme.primary,
            backgroundColor: colorScheme.surfaceContainerHighest,
          ),
        ],
      ]),
    );
  }

  int _tokenValue(UsageToken token) => switch (token) {
        UsageToken.input => stats.totalInput,
        UsageToken.cache => stats.totalCache,
        UsageToken.output => stats.totalOutput,
      };

  /// An em dash, not "0.0%": with no prompt tokens in range the cache was
  /// never asked, which is not the same as never hit.
  String _rateText(double? rate) => rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%';

  /// Grouped digits: these run to seven figures, and `443,807` is legible at a
  /// glance where `443807` has to be counted.
  String _fmt(int value) => NumberFormat.decimalPattern().format(value);
}
