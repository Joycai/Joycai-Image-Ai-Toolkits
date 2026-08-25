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

  /// Tool steps the running turn has taken so far. Null while nothing is
  /// running; zero while the agent is thinking but has called nothing yet.
  final int? runningSteps;

  /// Knowledge edits staged and waiting on the user. `10h` gives them the
  /// header's primary slot while there are any: in library-edit mode the
  /// session's product is the changes, not a prompt to apply.
  final int pendingKbEdits;
  final VoidCallback? onWriteAllKbEdits;
  final VoidCallback? onDiscardAllKbEdits;

  const PromptOptimizerToolbar({
    super.key,
    required this.onNewSession,
    required this.onHistory,
    required this.onApply,
    required this.isRefining,
    required this.canApply,
    this.modeLabel,
    this.modeIcon = Icons.smart_toy_outlined,
    this.runningSteps,
    this.pendingKbEdits = 0,
    this.onWriteAllKbEdits,
    this.onDiscardAllKbEdits,
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
                    if (runningSteps != null) ...[
                      const SizedBox(width: 8),
                      // `10i` states the run in the header, beside the mode it
                      // is running in: the transcript can be scrolled away
                      // from the card that is moving, and a disabled composer
                      // says only that typing is blocked, not that anything is
                      // happening.
                      //
                      // Flexible like its two neighbours. Three loose children
                      // share the row's free space and each sizes to its own
                      // content within its share, so a squeezed header
                      // ellipsizes rather than overflowing — which a fixed
                      // third pill on a 520px panel would.
                      Flexible(flex: 2, child: _runningPill(colorScheme, textTheme, l10n)),
                    ],
                  ],
                ),
        ),

        // Only in the compact header, where the running pill above is not
        // drawn at all: at full width the pill *is* the progress report, and a
        // spinner beside it said the same thing twice.
        if (isRefining && compact)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),

        if (!compact) ...[
          AppIconButton(
            icon: Icons.history,
            tooltip: l10n.optHistory,
            // Off during a turn: restoring another conversation mid-run swaps
            // the session out from under the agent, and starting a new one
            // leaves the running turn writing into a transcript nobody is
            // looking at. `10i` dims both.
            onPressed: isRefining ? null : onHistory,
          ),
          const SizedBox(width: 6),
          AppIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: l10n.optNewSession,
            onPressed: isRefining ? null : onNewSession,
          ),
          const ToolHeaderDivider(),
        ],

        // The one action the whole screen builds towards, and the only solid
        // accent on it. Disabled is an outline rather than a grey slab: there
        // is nothing to apply until the agent has produced a prompt, and a
        // filled grey button looks broken where an empty one reads as "not
        // yet".
        //
        // Staged knowledge edits outrank it, per `10h`. Nothing is on disk
        // until they are answered, so leaving the header pointing at the
        // workbench while three files wait for a decision aims the user at the
        // wrong screen — and applying a prompt does not resolve them.
        if (pendingKbEdits > 0) ...[
          if (!compact) ...[
            AppButton(
              label: l10n.kbEditDiscardAll,
              variant: AppButtonVariant.secondary,
              onPressed: onDiscardAllKbEdits,
            ),
            const SizedBox(width: 6),
          ],
          AppButton(
            label: compact
                ? l10n.kbEditApply
                : l10n.kbEditConfirmAll(pendingKbEdits),
            icon: Icons.save_outlined,
            onPressed: onWriteAllKbEdits,
          ),
        ] else
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

  /// "Running · step 8", with the pulsing dot `10i` draws.
  ///
  /// Same capsule as the mode badge beside it, deliberately: they are two
  /// facts about one session, and giving the live one its own shape made the
  /// header read as two unrelated widgets. The dot is what separates them.
  Widget _runningPill(ColorScheme colorScheme, TextTheme textTheme, AppLocalizations l10n) {
    final steps = runningSteps ?? 0;
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
          // Static, though `10i` pulses it — for the reason recorded on
          // [AppStatusBadge]: a repeating animation makes `pumpAndSettle`
          // never return and the screenshot harness capture a different frame
          // each run. The dot's presence is what carries the state.
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colorScheme.onAccentTint, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              steps == 0 ? l10n.optRunning : l10n.optRunningStep(steps),
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(color: colorScheme.onAccentTint),
            ),
          ),
        ],
      ),
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
