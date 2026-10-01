import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'usage_chrome.dart';
import 'usage_palette.dart';
import 'usage_stats.dart';

/// Composition is over all tokens; cache hit rate is over prompt tokens only.
class UsageTokenCharts extends StatelessWidget {
  const UsageTokenCharts({super.key, required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final breakdown = _breakdown(context);
        final cache = _cache(context, compact: constraints.maxWidth < 560);
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              breakdown,
              const SizedBox(height: AppSpace.s10),
              cache,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: breakdown),
            const SizedBox(width: AppSpace.s10),
            Expanded(child: cache),
          ],
        );
      },
    );
  }

  Widget _panel(BuildContext context, Widget child) => Container(
    padding: const EdgeInsets.all(AppSpace.s16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.control),
    ),
    child: child,
  );

  Widget _breakdown(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final values = [stats.totalInput, stats.totalCache, stats.totalOutput];
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final shares = [for (final value in values) total == 0 ? 0.0 : value / total];
    final colors = [for (final token in UsageToken.values) token.colorOf(context)];
    final exact = NumberFormat.decimalPattern().format(total);
    final legend = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, token) in UsageToken.values.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
            child: Tooltip(
              message:
                  '${token.labelOf(l10n)}: ${NumberFormat.decimalPattern().format(values[index])}',
              child: Row(
                children: [
                  UsageDot(colors[index]),
                  const SizedBox(width: AppSpace.s6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          token.labelOf(l10n),
                          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          NumberFormat.decimalPattern().format(values[index]),
                          style: text.bodyMedium?.mono.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(width: AppSpace.s6),
                    Text(
                      '${(shares[index] * 100).toStringAsFixed(1)}%',
                      style: text.labelSmall?.mono.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
    final ring = Tooltip(
      message: '${l10n.usageTotalTokens}: $exact',
      child: SizedBox.square(
        dimension: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(
                  key: const ValueKey('usage-token-donut'),
                  painter: UsageTokenDonutPainter(
                    shares: shares,
                    colors: colors,
                    track: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    child: Text(
                      NumberFormat.compact().format(total),
                      style: text.headlineMedium?.mono,
                    ),
                  ),
                  Text(
                    l10n.usageTotalTokens,
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UsageCaption(l10n.usageTokenBreakdown),
          const SizedBox(height: AppSpace.s10),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 300) {
                return Column(
                  children: [
                    ring,
                    const SizedBox(height: AppSpace.s10),
                    legend,
                  ],
                );
              }
              return Row(
                children: [
                  ring,
                  const SizedBox(width: AppSpace.s16),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cache(BuildContext context, {required bool compact}) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rate = stats.cacheHitRate;
    final label = rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%';
    final gauge = Semantics(
      label: '${l10n.cacheHitRate}: $label',
      child: SizedBox.square(
        dimension: compact ? 80 : 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CircularProgressIndicator(
                  key: const ValueKey('usage-cache-gauge'),
                  value: rate ?? 0,
                  strokeWidth: AppSpace.s10,
                  strokeAlign: BorderSide.strokeAlignInside,
                  color: scheme.primary,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
            Text(
              label,
              style: text.headlineMedium?.mono.copyWith(
                color: rate == null ? scheme.onSurfaceVariant : scheme.onAccentTint,
              ),
            ),
          ],
        ),
      ),
    );
    final hint = Text(
      l10n.cacheHitRateHint,
      textAlign: compact ? TextAlign.start : TextAlign.center,
      style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
    );
    return _panel(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: UsageCaption(l10n.cacheHitRate)),
              Tooltip(
                message: l10n.cacheHitRateHint,
                child: Icon(
                  Icons.help_outline,
                  size: AppSize.iconSm,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s10),
          if (compact)
            Row(
              children: [
                gauge,
                const SizedBox(width: AppSpace.s16),
                Expanded(child: hint),
              ],
            )
          else ...[
            Center(child: gauge),
            const SizedBox(height: AppSpace.s10),
            hint,
          ],
        ],
      ),
    );
  }
}

/// Draws disjoint, proportional sectors. Empty ranges retain only the track.
class UsageTokenDonutPainter extends CustomPainter {
  UsageTokenDonutPainter({required this.shares, required this.colors, required this.track});

  final List<double> shares;
  final List<Color> colors;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = AppSpace.s10;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(rect, paint..color = track);
    var start = -math.pi / 2;
    for (var i = 0; i < shares.length; i++) {
      final sweep = shares[i] * math.pi * 2;
      if (sweep > 0) canvas.drawArc(rect, start, sweep, false, paint..color = colors[i]);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(UsageTokenDonutPainter oldDelegate) =>
      !listEquals(shares, oldDelegate.shares) ||
      !listEquals(colors, oldDelegate.colors) ||
      track != oldDelegate.track;
}
