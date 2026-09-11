import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/context_usage_palette.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/assistant_context_usage.dart';

/// A card in the Prompt Assistant's side columns (`A3a` / `A3b`): the panel
/// ground laid on the column, a hairline, r16, a 10px inset and an 8px rhythm
/// between its rows.
///
/// Its own widget rather than `AppCard`: that one is r10 on the near-white
/// rung with a panel-edge outline, which is the previous system's card. These
/// columns are the one place the liquid-glass frames draw a stack of r16
/// cards, and every panel of the assistant shares this file already.
class OptimizerPanelCard extends StatelessWidget {
  const OptimizerPanelCard({super.key, required this.children});

  final List<Widget> children;

  /// The spec's `gap:8` inside a card. Off the 4/6/10 ladder, as drawn.
  static const double gap = 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Material, not a decorated box: buttons and links inside draw their ink
    // on the nearest Material, and a fill painted above that would hide it.
    return Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) const SizedBox(height: gap),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

/// The 11/500 tracked caption in the deep ink that heads a card or a column,
/// with an optional figure or action on its right.
///
/// Upper-cased like `AppSectionLabel`, which the rest of the app heads its
/// groups with: a no-op on CJK, and the spec's caption is upper case in the
/// Latin locales (`EXECUTION LOGS`).
class OptimizerPanelCaption extends StatelessWidget {
  const OptimizerPanelCaption(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: AppType.trackedLabelSpacing,
                  color: colorScheme.onAccentTint,
                ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpace.s6),
          trailing!,
        ],
      ],
    );
  }
}

/// A small r4 label on a container colour — a status (`Ready`, `Unsaved`) or,
/// with [mono], a file's change kind (`edited`, `new`).
class OptimizerTagBadge extends StatelessWidget {
  const OptimizerTagBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.leading,
    this.mono = false,
  });

  final String label;
  final Color background;
  final Color foreground;

  /// A dot or glyph before the label — the knowledge card's breathing dot.
  final Widget? leading;

  /// The tree's and the pending list's `edited` / `new`: mono 11/600 in a
  /// tighter box, where the status form is 11/500 in the sans face.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: mono
          ? const EdgeInsets.symmetric(horizontal: 5, vertical: 1)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpace.s4),
          ],
          Text(
            label,
            maxLines: 1,
            style: mono
                ? textTheme.labelSmall?.mono.copyWith(fontWeight: FontWeight.w600, color: foreground)
                : textTheme.labelSmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

/// How much of the model's context window this session is spending, and on
/// what.
///
/// The slices are parts of one whole, not conditions. `A3a` / `A3b` draw them
/// as the accent (system prompt), a fixed steel blue (tool definitions — a
/// different blue rather than a lighter one, so it survives next to a blue
/// accent), the warning amber (the conversation, the one slice compaction acts
/// on and the one that grows until something gives) and the track (what is
/// left).
///
/// Purely presentational: every number arrives measured, from
/// `PromptOptimizerAgent.measureContext`.
class OptimizerContextCard extends StatelessWidget {
  final ContextUsageSnapshot usage;

  /// A line under the legend explaining something about *this mode's* usage.
  /// Null in the modes that have nothing to explain.
  final String? note;

  const OptimizerContextCard({
    super.key,
    this.usage = ContextUsageSnapshot.placeholder,
    this.note,
  });

  /// The stacked bar's height, and the radius that caps its ends.
  static const double _barHeight = 8;

  static const double _dotSize = 6;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;

    final colors = <ContextUsageSlice, Color>{
      ContextUsageSlice.systemPrompt: colorScheme.primary,
      ContextUsageSlice.tools: ContextUsagePalette.of(ContextUsageSlice.tools, colorScheme.brightness),
      ContextUsageSlice.history: semantic.warning,
    };
    final remaining = colorScheme.surfaceContainerHighest;
    final labels = <ContextUsageSlice, String>{
      ContextUsageSlice.systemPrompt: l10n.optCtxSystemPrompt,
      ContextUsageSlice.tools: l10n.optCtxTools,
      ContextUsageSlice.history: l10n.optCtxHistory,
    };
    final noteStyle = textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
      height: AppType.looseHeight,
    );

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.optCtxTitle,
          trailing: _buildReadout(l10n, colorScheme, textTheme),
        ),
        _buildBar(colors, remaining),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              dot: remaining,
              label: l10n.optCtxRemaining,
              // An unlimited model has real figures and no ceiling: there is no
              // remainder to report, and a "0 left" there would be backwards.
              value: usage.hasWindow ? usage.remainingChars : null,
            ),
          ],
        ),
        // Said once, under the numbers it qualifies: the window being drawn is
        // the default the compaction budget assumes, not this model's.
        if (usage.basis == ContextWindowBasis.assumed) Text(l10n.optCtxWindowAssumed, style: noteStyle),
        if (note != null) Text(note!, style: noteStyle),
      ],
    );
  }

  /// `102.2K / 200K` in mono — the spent half in the body ink, the window in
  /// the secondary one, so the ratio reads before the digits do.
  Widget _buildReadout(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final base = textTheme.labelSmall?.mono.copyWith(fontWeight: FontWeight.w400);
    if (usage.isUnknown) {
      return Text(
        l10n.optCtxWindowUnknown,
        style: base?.copyWith(color: colorScheme.onSurfaceVariant),
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _formatChars(usage.usedChars),
            style: base?.copyWith(color: colorScheme.onSurface),
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

  /// The stacked bar: three slices over the remainder they are drawn from.
  ///
  /// [LayoutBuilder] with explicit widths rather than `Expanded(flex:)` —
  /// `flex` must be at least 1, so a zero-length slice (which an unmeasured or
  /// unlimited session makes all three) would assert rather than not draw.
  Widget _buildBar(Map<ContextUsageSlice, Color> colors, Color remaining) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: SizedBox(
        height: _barHeight,
        child: ColoredBox(
          color: remaining,
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

  /// One legend pair: dot and label on the left, the figure on the right.
  /// Rows rather than a wrapping grid — the column narrows to 250px, and a
  /// label must ellipsize there without clipping the figure beside it.
  Widget _buildLegendRow(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required Color dot,
    required String label,
    required int? value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: OptimizerPanelCard.gap),
          Text(
            value == null ? '—' : _formatChars(value),
            style: textTheme.labelSmall?.mono.copyWith(
              fontWeight: FontWeight.w400,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// `18.2K` past a thousand, `1.6M` past a million, the bare figure below
  /// both. The `M` step keeps a 1M-token window from reading `1572.9K` and
  /// pushing the readout into the caption at 250px.
  static String _formatChars(int chars) {
    if (chars < 1000) return '$chars';
    if (chars < 1000000) return '${(chars / 1000).toStringAsFixed(1)}K';
    return '${(chars / 1000000).toStringAsFixed(1)}M';
  }
}
