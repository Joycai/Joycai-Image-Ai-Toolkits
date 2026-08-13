import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_icon_button.dart';
import 'workbench_tool_header.dart';

/// Panel width below which this header drops to its compact form.
///
/// Measured against the header, not against the app's mobile breakpoint: the
/// full form spends ~320px on chrome that cannot shrink (back button, two
/// session icons, the divider and the "apply to workbench" button) and needs
/// another ~200 before the title and mode badge are worth reading. Note this
/// is *below* the workbench's own centre panel at the default desktop layout —
/// 1440 minus the rail, both side panels and two gutters leaves it 568 — so
/// the number has to sit between that and [kMinCenterWidth], not at 600.
const double _kCompactHeaderWidth = 520;

/// The prompt assistant's header: leave, see which brain is answering, reach
/// the session controls, and apply the result.
///
/// Built on [WorkbenchToolHeader] like the comparator, mask and crop tools.
/// It is the reason that widget exists: this header had no back button at all,
/// so the one screen the user is most likely to arrive at from a card action
/// was also the only one with no way back to the gallery except the tab strip.
class PromptOptimizerToolbar extends StatelessWidget {
  final VoidCallback onNewSession;
  final VoidCallback onHistory;
  final VoidCallback onApply;
  final bool isRefining;
  final bool canApply;

  /// Localised name of the session's mode, shown as a badge beside the title.
  /// Null hides the badge.
  final String? modeLabel;

  /// Glyph for that badge — one per mode, so the three read apart at a glance
  /// rather than only by their words.
  final IconData modeIcon;

  const PromptOptimizerToolbar({
    super.key,
    required this.onNewSession,
    required this.onHistory,
    required this.onApply,
    required this.isRefining,
    required this.canApply,
    this.modeLabel,
    this.modeIcon = Icons.smart_toy_outlined,
  });

  @override
  Widget build(BuildContext context) {
    // Compact form is decided by the panel this header was handed, not by the
    // screen. Of the four tools this is the only one whose tab keeps both side
    // panels, so it is the only header that can find itself in a column far
    // narrower than the window — where `Responsive.isMobile` still answers
    // "desktop" and lays out ~290px of chrome that does not fit.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _build(context, constraints.maxWidth < _kCompactHeaderWidth),
    );
  }

  Widget _build(BuildContext context, bool compact) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return WorkbenchToolHeader(
      children: [
        const SizedBox(width: 10),

        // Title and badge fill the leading space, pushing the actions right.
        Expanded(
          child: compact
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    // Given a third of the space, against the badge's two:
                    // equal [Flexible]s split the row evenly and the title's
                    // unused half is not handed back, which is what cut the
                    // badge to "知识库 · Ag…" while the title sat in space it
                    // wasn't using. The badge is the longer string in all four
                    // languages, so it gets the larger share; the title still
                    // has to be able to ellipsise, because "プロンプトアシス
                    // タント" beside a Japanese badge does not fit a squeezed
                    // panel at any share.
                    Flexible(
                      child: Text(
                        l10n.promptOptimizer,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: textTheme.titleMedium,
                      ),
                    ),
                    if (modeLabel != null) ...[
                      const SizedBox(width: 10),
                      // Which brain is answering. The three modes behave very
                      // differently and the setting that picks them lives in a
                      // panel that can be closed, so the header has to say it.
                      //
                      // The spec draws this as an accent-tinted capsule — one
                      // of the three places accent is allowed (selection, main
                      // CTA, badge). It was a grey `surfaceContainerHighest`
                      // box, which read as a disabled control rather than as a
                      // statement about the session.
                      Flexible(flex: 2, child: _modeBadge(colorScheme, textTheme, l10n)),
                    ],
                  ],
                ),
        ),

        if (isRefining)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),

        if (!compact) ...[
          AppIconButton(
            icon: Icons.history,
            tooltip: l10n.optHistory,
            onPressed: onHistory,
          ),
          const SizedBox(width: 6),
          AppIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: l10n.optNewSession,
            onPressed: onNewSession,
          ),
          const ToolHeaderDivider(),
        ],

        // The one action the whole screen builds towards, and the only solid
        // accent on it. Disabled is an outline rather than a grey slab: there
        // is nothing to apply until the agent has produced a prompt, and a
        // filled grey button looks broken where an empty one reads as "not
        // yet".
        AppButton(
          label: compact ? l10n.apply : l10n.applyToWorkbench,
          icon: Icons.check,
          variant: canApply ? AppButtonVariant.primary : AppButtonVariant.secondary,
          onPressed: canApply ? onApply : null,
        ),

        if (compact) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: (value) {
              if (value == 'new_session') onNewSession();
              if (value == 'history') onHistory();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(l10n.optHistory),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'new_session',
                child: ListTile(
                  leading: const Icon(Icons.add_comment_outlined),
                  title: Text(l10n.optNewSession),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _modeBadge(ColorScheme colorScheme, TextTheme textTheme, AppLocalizations l10n) {
    return Container(
      height: AppSize.compact,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(modeIcon, size: 13, color: colorScheme.onAccentTint),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              l10n.optModeBadgeAgent(modeLabel!),
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.onAccentTint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
