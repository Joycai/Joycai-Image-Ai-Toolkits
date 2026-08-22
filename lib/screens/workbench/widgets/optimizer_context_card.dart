import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/context_usage_palette.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/assistant_context_usage.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_section_label.dart';

/// How much of the model's context window this session is spending, and on
/// what.
///
/// The three slices are *identity* colours, not conditions — they tell parts of
/// one whole apart rather than reporting success or trouble. They borrow
/// [AppSemanticColors.info] and `warning` because those are the only
/// seed-independent hues the app has and the bar has exactly three parts; a
/// fourth slice would be the point to give it its own palette module beside
/// `core/fee_group_palette.dart`.
///
/// Purely presentational: every number arrives measured, from
/// `PromptOptimizerAgent.measureContext`.
class OptimizerContextCard extends StatelessWidget {
  final ContextUsageSnapshot usage;

  const OptimizerContextCard({super.key, this.usage = ContextUsageSnapshot.placeholder});

  /// The height of the stacked bar. Under [AppRadius] territory — it is a rule,
  /// not a container — so it stays a literal beside the pill radius that caps
  /// its ends.
  static const double _barHeight = 8;

  static const double _dotSize = 8;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Its own palette since the restyle, not `primary` / `info` / `warning`.
    // The default seed is blue and `semantic.info` is also blue, so the first
    // two slices — the two that sit side by side — came out the same colour.
    // See [ContextUsagePalette] for why these are identity colours rather than
    // theme roles.
    final brightness = colorScheme.brightness;
    final colors = <ContextUsageSlice, Color>{
      for (final slice in ContextUsageSlice.values)
        slice: ContextUsagePalette.of(slice, brightness),
    };
    final labels = <ContextUsageSlice, String>{
      ContextUsageSlice.systemPrompt: l10n.optCtxSystemPrompt,
      ContextUsageSlice.tools: l10n.optCtxTools,
      ContextUsageSlice.history: l10n.optCtxHistory,
    };

    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSectionLabel(
            l10n.optCtxTitle,
            padding: EdgeInsets.zero,
            trailing: _buildReadout(l10n, colorScheme, textTheme),
          ),
          const SizedBox(height: 10),
          _buildBar(colorScheme, colors),
          const SizedBox(height: 10),
          for (final slice in ContextUsageSlice.values)
            _buildLegendRow(
              colorScheme,
              textTheme,
              dot: colors[slice]!,
              label: labels[slice]!,
              // A missing key is a slice nobody has measured yet — '—', not a
              // zero the user would read as "this costs nothing".
              value: usage.isUnknown ? null : usage.slices[slice],
            ),
          _buildLegendRow(
            colorScheme,
            textTheme,
            dot: ContextUsagePalette.remaining(colorScheme.brightness),
            label: l10n.optCtxRemaining,
            // An unlimited model has real figures and no ceiling: the three
            // slices still say what was spent, but there is no remainder to
            // report and a "0 left" there would be exactly backwards.
            value: usage.hasWindow ? usage.remainingChars : null,
            muted: true,
          ),
          // Said once, under the numbers it qualifies: the window being drawn
          // is not this model's, it is the default the compaction budget also
          // assumes. Without it the bar claims a measurement it doesn't have.
          if (usage.basis == ContextWindowBasis.assumed) ...[
            const SizedBox(height: 6),
            Text(
              l10n.optCtxWindowAssumed,
              style: textTheme.labelSmall?.copyWith(color: colorScheme.outline, height: AppType.looseHeight),
            ),
          ],
        ],
      ),
    );
  }

  /// `102.2K / 200K` — the spent half in the body colour, the window it is
  /// spent against in the muted one, so the ratio reads before the digits do.
  Widget _buildReadout(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    if (usage.isUnknown) {
      return Text(
        l10n.optCtxWindowUnknown,
        style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      );
    }

    final base = textTheme.labelMedium?.mono;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _formatChars(usage.usedChars),
            style: base?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
          ),
          TextSpan(
            text: usage.hasWindow
                ? ' / ${_formatChars(usage.windowChars)}'
                : ' / ${l10n.optCtxWindowUnlimited}',
            style: base?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// The stacked bar: three slices over the window they are drawn from.
  ///
  /// [LayoutBuilder] with explicit widths rather than `Expanded(flex:)` —
  /// `flex` must be at least 1, so a zero-length slice (which an unmeasured or
  /// unlimited session makes all three) would assert rather than simply not
  /// draw.
  Widget _buildBar(ColorScheme colorScheme, Map<ContextUsageSlice, Color> colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: _barHeight,
        child: ColoredBox(
          // The unfilled remainder of the bar, which is the same thing the
          // "remaining window" legend dot names — so it takes the same colour.
          color: ContextUsagePalette.remaining(colorScheme.brightness),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                for (final slice in ContextUsageSlice.values)
                  SizedBox(
                    width: constraints.maxWidth * usage.fractionOf(slice),
                    child: ColoredBox(color: colors[slice]!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendRow(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required Color dot,
    required String label,
    required int? value,
    bool muted = false,
  }) {
    final valueColor = muted ? colorScheme.onSurfaceVariant : colorScheme.onSurface;

    // Four rows rather than a grid: the right panel narrows to 250px, and a
    // two-column grid there cannot ellipsize the label without also clipping
    // the figure beside it.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value == null ? '—' : _formatChars(value),
            style: textTheme.labelMedium?.mono.copyWith(
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  /// `18.2K` past a thousand, `1.6M` past a million, the bare figure below
  /// both. Locale-independent on purpose: this is a magnitude beside a coloured
  /// slice, not a quantity the user is expected to do arithmetic with.
  ///
  /// The `M` step is not cosmetic — a 1M-token model's window is `1572.9K`,
  /// which is four digits of precision nobody reads and which pushes the
  /// readout into the title beside it at 250px.
  static String _formatChars(int chars) {
    if (chars < 1000) return '$chars';
    if (chars < 1000000) return '${(chars / 1000).toStringAsFixed(1)}K';
    return '${(chars / 1000000).toStringAsFixed(1)}M';
  }
}
