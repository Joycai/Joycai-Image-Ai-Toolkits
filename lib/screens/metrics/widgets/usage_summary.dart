import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/panel_resizer.dart';
import 'usage_stats.dart';

/// Accent per metric. Shared with the fee-group price pills and the record
/// list, so a rate, a token count and a cost keep one colour across the app.
const Color usageInputAccent = Colors.blue;
const Color usageCacheAccent = Colors.teal;
const Color usageOutputAccent = Colors.green;
const Color usageRequestAccent = Colors.purple;
const Color usageCostAccent = Colors.orange;

/// The summary block above the usage records, shared by every breakpoint.
///
/// Cost gets a card to itself because it is the number the screen exists to
/// answer; the three token counts share a second card with the cache hit rate,
/// which is derived from two of them — a meter next to its own numerator and
/// denominator needs no explaining. Six equal tiles said all of that was
/// equally important and left nothing room to breathe.
///
/// [compact] stacks the two cards instead of setting them side by side, for
/// mobile and the tablet card.
class UsageSummary extends StatelessWidget {
  final UsageStats stats;

  /// The active range preset, named — "Last Week", not the dates it resolved
  /// to. Every number on these cards is a total *over that range*, and a total
  /// with no period attached is not a fact. The resolved dates are spelled out
  /// beside the presets below, where changing them is possible.
  final String rangeLabel;

  final bool compact;

  const UsageSummary({
    super.key,
    required this.stats,
    required this.rangeLabel,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final cost = _buildCostCard(context, l10n, colorScheme);
    final tokens = _buildTokenCard(context, l10n, colorScheme);

    if (compact) {
      return Column(
        children: [
          cost,
          const SizedBox(height: 8),
          tokens,
        ],
      );
    }

    // IntrinsicHeight so the shorter cost card matches the token card rather
    // than floating at its own height beside it.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: cost),
          const SizedBox(width: 8),
          Expanded(flex: 7, child: tokens),
        ],
      ),
    );
  }

  /// The shell both cards share.
  ///
  /// Wide layouts sit on the screen's `surfaceContainer` canvas, where a
  /// `surface` PanelCard reads as a card. Compact ones are hosted inside
  /// another surface-coloured card (tablet) or straight on the scaffold
  /// (mobile) — surface on surface would vanish, so those step up a tone.
  Widget _card(BuildContext context, Widget child) {
    if (!compact) return PanelCard(child: child);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  // --- Cost ---------------------------------------------------------------

  /// The one card that is tinted rather than plain, because it holds the one
  /// number the screen is for. The tint does the emphasising, which frees the
  /// figure itself to stay `onSurface`: an orange number on an orange wash
  /// would be less legible, not more emphatic, and the token counts beside it
  /// need their own accents to stay distinguishable from each other.
  Widget _buildCostCard(BuildContext context, AppLocalizations l10n, ColorScheme colorScheme) {
    return _card(
      context,
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.9, -1.1),
            radius: 1.4,
            colors: [
              usageCostAccent.withAlpha(38),
              usageCostAccent.withAlpha(8),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconTile(Icons.attach_money, usageCostAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.estimatedCost,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '\$${stats.totalCost.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    fontFamily: 'monospace',
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildCostFooter(context, l10n, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  /// What the cost is a cost *of*: a count of requests, and the period both
  /// numbers cover.
  Widget _buildCostFooter(BuildContext context, AppLocalizations l10n, ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: usageRequestAccent.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${_fmt(stats.totalRequestCount)} ${l10n.requests}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: usageRequestAccent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            rangeLabel,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // --- Tokens + hit rate --------------------------------------------------

  Widget _buildTokenCard(BuildContext context, AppLocalizations l10n, ColorScheme colorScheme) {
    return _card(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tokenStat(context, usageInputAccent, l10n.inputTokens, stats.totalInput),
                _tokenStat(context, usageCacheAccent, l10n.cachedInputTokens, stats.totalCache),
                _tokenStat(context, usageOutputAccent, l10n.outputTokens, stats.totalOutput),
              ],
            ),
            const SizedBox(height: 18),
            _buildHitRateMeter(context, l10n, colorScheme),
          ],
        ),
      ),
    );
  }

  /// A label and its number. The accent on the number is the only marker each
  /// stat carries — an icon per label repeated the colour without adding to it,
  /// and three icons in a row read as a toolbar, not as figures.
  Widget _tokenStat(BuildContext context, Color accent, String label, int value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _fmt(value),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: accent,
                fontFamily: 'monospace',
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The hit rate reads as a meter rather than a sixth counter — it is a share
  /// of the two numbers directly above it, and a bar says "of the whole" in a
  /// way a bare percentage does not.
  Widget _buildHitRateMeter(BuildContext context, AppLocalizations l10n, ColorScheme colorScheme) {
    final rate = stats.cacheHitRate;

    return Tooltip(
      message: l10n.cacheHitRateHint,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.cacheHitRate,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                // An em dash, not "0.0%": with no prompt tokens in range the
                // cache was never asked, which is not the same as never hit.
                rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: rate == null ? colorScheme.outline : usageCacheAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate ?? 0,
              minHeight: 6,
              backgroundColor: usageCacheAccent.withAlpha(30),
              valueColor: const AlwaysStoppedAnimation(usageCacheAccent),
            ),
          ),
        ],
      ),
    );
  }

  /// The rounded accent tile the app puts in front of a heading — same shape
  /// the fee-group rows and dialog headers use.
  Widget _iconTile(IconData icon, Color accent) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: accent.withAlpha(35),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 17, color: accent),
    );
  }

  /// Grouped digits: these run to seven figures, and `443,807` is legible at a
  /// glance where `443807` has to be counted.
  String _fmt(int value) => NumberFormat.decimalPattern().format(value);
}
