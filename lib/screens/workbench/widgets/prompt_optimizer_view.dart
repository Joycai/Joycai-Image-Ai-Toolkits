import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../core/text_diff.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/assistant/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/ui/app_breathing_dot.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_snackbar.dart';
import '../../../widgets/ui/dashed_border.dart';
import 'result_feedback_labels.dart';

part 'optimizer/optimizer_agent_timeline.dart';
part 'optimizer/optimizer_ask_user_card.dart';
part 'optimizer/optimizer_card_chrome.dart';
part 'optimizer/optimizer_composer.dart';
part 'optimizer/optimizer_distill_cards.dart';
part 'optimizer/optimizer_feedback_card.dart';
part 'optimizer/optimizer_kb_edit_card.dart';
part 'optimizer/optimizer_prompt_card.dart';

/// One row of the transcript as drawn, which is not one-to-one with
/// [OptimizerChatEntry]: a run of consecutive tool calls collapses into a
/// single timeline card.
class _TranscriptRow {
  /// Transcript index of the first entry, used as a stable expand-state key.
  final int startIndex;
  final List<OptimizerChatEntry> entries;

  _TranscriptRow({required this.startIndex, required this.entries});

  bool get isToolGroup => entries.first.kind == OptimizerEntryKind.tool;
}

/// Multi-turn chat view for the prompt-optimizer agent.
///
/// Renders the session transcript (user turns, assistant replies, tool-call
/// timelines, staged prompt versions, knowledge edits, questions) with the
/// composer pinned at the bottom. The heavy lifting happens in
/// [PromptOptimizerAgent]; this widget only observes the session.
///
/// Drawn to `A3a 提示词助手-对话` (and `A3b · 1a` for the knowledge-edit
/// cards): the column sits on `surface`, every message is opaque content on
/// it, and the assistant's side of the conversation hangs off a 26px avatar
/// column — its cards indent under that avatar so a reply and the cards it
/// produced read as one turn.
class PromptOptimizerChatView extends StatefulWidget {
  final TextEditingController inputCtrl;
  final VoidCallback onSend;
  final VoidCallback onRetry;
  final void Function(String prompt) onApplyPrompt;

  /// Writes a staged knowledge-base edit to disk after the user approves it.
  final void Function(String editId) onApplyKbEdit;

  /// Discards a staged knowledge-base edit.
  final void Function(String editId) onRejectKbEdit;

  /// Sends the user's answers to a pending ask_user question card.
  final void Function(String callId, List<AskUserAnswer> answers) onAnswerAskUser;
  final bool isBusy;

  /// Cancels the queued or running turn. Null when there is nothing to stop —
  /// which is also what hides the composer's abort control.
  final VoidCallback? onAbort;

  /// Stages and runs the "distill this session into the knowledge base"
  /// request (`20d`). Null hides the composer chip entirely — the screen only
  /// passes it for knowledge sessions.
  final VoidCallback? onDistill;

  /// Opens the prompt-library save dialog prefilled with the final staged
  /// prompt, from the distill wrap-up card's footer (`20d`·d).
  final VoidCallback? onSaveFinalPrompt;

  /// Opens the assistant model's editor, from a reply cut at the output
  /// limit — the fix lives in that model's max-output setting, and the screen
  /// knows which model that is. Null hides the jump.
  final VoidCallback? onOpenModelSettings;

  const PromptOptimizerChatView({
    super.key,
    required this.inputCtrl,
    required this.onSend,
    required this.onRetry,
    required this.onApplyPrompt,
    required this.onApplyKbEdit,
    required this.onRejectKbEdit,
    required this.onAnswerAskUser,
    required this.isBusy,
    this.onAbort,
    this.onDistill,
    this.onSaveFinalPrompt,
    this.onOpenModelSettings,
  });

  @override
  State<PromptOptimizerChatView> createState() => _PromptOptimizerChatViewState();
}

class _PromptOptimizerChatViewState extends State<PromptOptimizerChatView> {
  final ScrollController _scrollCtrl = ScrollController();
  PromptOptimizerSession? _session;
  int _lastTranscriptLength = 0;

  /// Edit ids whose full proposed content is expanded. Purely presentational.
  final Set<String> _expandedKbEdits = {};

  /// Transcript indices of tool groups the user has opened, and prompt cards
  /// whose full text is showing. Both keyed by transcript index, which is
  /// stable because the transcript is append-only.
  final Set<int> _expandedToolGroups = {};
  final Set<int> _expandedPrompts = {};

  /// Steps shown before a timeline card needs opening. Three is enough to see
  /// what kind of work the agent did without the card becoming the page.
  static const int _collapsedStepCount = 3;

  /// A prompt longer than this folds. Roughly the point where the card starts
  /// pushing the reply that explains it off the screen.
  static const int _promptFoldChars = 600;
  static const double _promptFoldHeight = 196;

  /// Height of the fade that covers the cut edge of a folded prompt.
  static const double _promptFadeHeight = 44;

  /// How tall a knowledge diff is allowed to get before it scrolls
  /// inside itself. Roughly a screenful of the transcript: past that the
  /// card stops being a review of one change and becomes the page.
  static const double _kbDiffMaxHeight = 320;

  /// Card width at which the staged-edit header still fits the path, the
  /// badge and the show-content link on one line. Measured against the
  /// *card*, not the window: the transcript is a column inside a panel that
  /// can be dragged narrow at any screen size.
  static const double _kbEditWideHeader = 440;

  /// `A3a`: the avatar square and the gap after it. Cards that belong to the
  /// assistant's turn indent by the sum, so they line up with its text.
  static const double _avatarSize = 26;
  static const double _avatarGap = 10;
  static const double _turnIndent = _avatarSize + _avatarGap;

  /// Reply text and cards stop at 720 (`A3a` 「正文最大宽 720」).
  static const double _bodyMaxWidth = 720;

  /// The conversation and the composer stop here on a very wide column and
  /// centre, so the user's bubble does not drift a monitor's width away from
  /// the reply it answers. Wider than any column the three-pane layout
  /// produces at 1440, where the design runs full width.
  static const double _transcriptMaxWidth = 960;

  static const double _userBubbleMaxWidth = 560;
  static const double _userBubbleMaxWidthPhone = 300;

  static const double _entryGap = 14;
  static const double _cardHeaderHeight = 40;

  /// Phone card actions: two equal buttons at this height (`A3a · 1d`).
  static const double _phoneActionHeight = 36;

  /// The user bubble's corners: 16 everywhere but the one pointing back at
  /// the right edge it is aligned to.
  static const Radius _bubbleRadius = Radius.circular(AppRadius.lg);
  static const Radius _tailRadius = Radius.circular(AppRadius.sm);

  /// [setState] for the builders in `optimizer/`. They are extensions on this
  /// class, and an extension may not call a protected member itself.
  void _rebuild(VoidCallback fn) => setState(fn);

  bool get _phone => Responsive.isMobile(context);
  double get _gutter => _phone ? 12 : 24;

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _attachSession(PromptOptimizerSession session) {
    if (identical(_session, session)) return;
    _session?.removeListener(_onSessionChanged);
    _session = session;
    _lastTranscriptLength = session.transcript.length;
    session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final length = _session?.transcript.length ?? 0;
    if (length != _lastTranscriptLength) {
      _lastTranscriptLength = length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    setState(() {});
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: AppMotion.durationOf(context, AppMotion.panel),
      curve: AppMotion.enter,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WorkbenchUIState>().optimizerSession;
    _attachSession(session);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    // `A3a`: the only workbench centre column with a ground of its own.
    return ColoredBox(
      color: colorScheme.surface,
      // The bottom console can be dragged up until this pane is only a couple
      // of hundred pixels tall. A composer that always reserves six lines then
      // leaves nothing for the conversation and overflows outright, so it is
      // capped against the height actually on offer.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final composerLines = switch (constraints.maxHeight) {
            < 240 => 1,
            < 340 => 3,
            _ => 6,
          };

          return Column(
            children: [
              Expanded(
                child: session.transcript.isEmpty
                    ? _buildEmptyState(l10n, colorScheme)
                    : _buildTranscript(session, l10n, colorScheme),
              ),
              _buildInputBar(session, l10n, colorScheme, composerLines),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    // Scrollable, not just centred: the input bar grows to six lines as the
    // user types, and the console below can be dragged up, so the space left
    // for this can fall below the artwork's own height. A bare Column cannot
    // shrink past its children and would overflow instead.
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: _gutter, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.accentTint,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(Icons.auto_awesome, size: 24, color: colorScheme.primary),
              ),
              const SizedBox(height: 14),
              Text(
                l10n.promptOptimizer,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.optEmptyChat,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.looseHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Collapses each run of consecutive tool calls into one row.
  ///
  /// A ten-step agent turn used to render as ten grey lines of the same weight
  /// as everything else, so the answer it produced was buried under the
  /// working-out. Grouping is done here rather than in the agent because it is
  /// purely presentational — the transcript itself stays one entry per call.
  ///
  /// Rows are keyed by the transcript index of their first entry, which is
  /// stable: the transcript is append-only, so an index never refers to a
  /// different entry later.
  static List<_TranscriptRow> _groupRows(List<OptimizerChatEntry> transcript) {
    final rows = <_TranscriptRow>[];
    for (var i = 0; i < transcript.length; i++) {
      final entry = transcript[i];
      final continuesGroup = entry.kind == OptimizerEntryKind.tool &&
          rows.isNotEmpty &&
          rows.last.isToolGroup;
      if (continuesGroup) {
        rows.last.entries.add(entry);
      } else {
        rows.add(_TranscriptRow(startIndex: i, entries: [entry]));
      }
    }
    return rows;
  }

  Widget _buildTranscript(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final rows = _groupRows(session.transcript);

    // Where the turn in flight shows itself. If it has already called a tool,
    // the trailing timeline card is that turn and takes the live treatment —
    // breathing dot, elapsed, held open, with the step it is working on at
    // the bottom. If it has not (the first request of a turn, or system-prompt
    // mode, which calls no tools at all), there is nothing in the transcript
    // to make live, so one card is appended to stand for it.
    //
    // The two flags are deliberately not the same one. Only a session that is
    // genuinely running may make an existing timeline card live — a *queued*
    // turn would otherwise light up the previous turn's card, which is
    // finished. But the standing card follows `isBusy`, so the wait between
    // enqueueing and starting is not a disabled composer with nothing in the
    // conversation to explain it.
    final bool liveTimeline =
        session.isRunning && rows.isNotEmpty && rows.last.isToolGroup;
    final int extra = widget.isBusy && !liveTimeline ? 1 : 0;
    // The distill wrap-up (`20d`·d), only once the turn is over and every
    // staged edit has been decided. Mutually exclusive with `extra` by
    // construction: one needs the turn running, the other needs it finished.
    // Anchored to the distill turn's end rather than the list tail — [wrapUpAt]
    // is the row index it is spliced in *before*, which equals rows.length
    // only while the distill is still the latest activity.
    final distill = widget.isBusy ? null : _distillOutcome(session.transcript);
    int? wrapUpAt;
    if (distill != null) {
      final at = rows.indexWhere((r) => r.startIndex >= distill.insertBefore);
      wrapUpAt = at < 0 ? rows.length : at;
    }
    final int wrapUp = wrapUpAt == null ? 0 : 1;

    return ListView.builder(
      controller: _scrollCtrl,
      // Bottom zero: every row already carries the 14px entry gap under it.
      padding: EdgeInsets.fromLTRB(_gutter, 12, _gutter, 0),
      itemCount: rows.length + extra + wrapUp,
      itemBuilder: (context, index) {
        final Widget child;
        if (extra == 1 && index == rows.length) {
          child = _buildRunningCard(session, l10n, colorScheme);
        } else if (wrapUpAt != null && index == wrapUpAt) {
          child = _buildDistillDoneCard(
              session, distill!.applied, l10n, colorScheme);
        } else {
          // Rows after the spliced-in wrap-up card shift by one.
          final rowIndex =
              (wrapUpAt != null && index > wrapUpAt) ? index - 1 : index;
          final row = rows[rowIndex];
          final isLast = rowIndex == rows.length - 1;
          child = row.isToolGroup
              ? _buildAgentTimeline(
                  row,
                  l10n,
                  colorScheme,
                  live: liveTimeline && isLast,
                  startedAt: session.runStartedAt,
                )
              : _buildEntry(row.entries.first, isLast, l10n, colorScheme);
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _transcriptMaxWidth),
            child: Padding(
              padding: const EdgeInsets.only(bottom: _entryGap),
              child: child,
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Shared pieces
  // ---------------------------------------------------------------------------

  Widget _buildEntry(OptimizerChatEntry entry, bool isLast, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;

    switch (entry.kind) {
      case OptimizerEntryKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: _phone ? _userBubbleMaxWidthPhone : _userBubbleMaxWidth,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: _bubbleRadius,
                topRight: _bubbleRadius,
                bottomLeft: _bubbleRadius,
                bottomRight: _tailRadius,
              ),
            ),
            child: SelectableText(
              entry.text,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                height: AppType.proseHeight,
              ),
            ),
          ),
        );

      case OptimizerEntryKind.assistant:
        // No bubble: the reply is plain text on the panel, owned by its avatar.
        return _besideAvatar(
          _avatar(Icons.auto_awesome, ground: colorScheme.accentTint, ink: colorScheme.primary),
          Padding(
            // Centres the first 13px line on the 26px avatar.
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarkdownBody(
                  data: entry.text,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: AppType.proseHeight,
                    ),
                  ),
                ),
                // The reply ends where the host cut it, not where the model
                // stopped: said at the tail, in the caption tone, with the
                // one place the fix lives.
                if (entry.truncated)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.s6),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.s6,
                      children: [
                        Icon(Icons.keyboard_tab, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
                        Text(
                          l10n.optTruncatedTail,
                          style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (widget.onOpenModelSettings != null)
                          AppButton(
                            label: l10n.optOpenModelSettings,
                            variant: AppButtonVariant.text,
                            size: AppButtonSize.compact,
                            onPressed: widget.onOpenModelSettings,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );

      case OptimizerEntryKind.tool:
        // Reached only for a lone tool call with no neighbours; a run of them
        // is grouped into the timeline card by _groupRows before this.
        return _besideAvatar(
          _avatar(
            Icons.build_outlined,
            ground: colorScheme.surfaceContainerHigh,
            ink: colorScheme.onSurfaceVariant,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _toolLabel(entry, l10n),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: AppType.proseHeight,
              ),
            ),
          ),
        );

      case OptimizerEntryKind.prompt:
        return _buildPromptCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.kbEdit:
        return _buildKbEditCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.askUser:
        // Keyed by call id so the draft selections survive the transcript
        // rebuilds that copyWith state flips trigger.
        return _underAvatar(
          _AskUserCard(
            key: ValueKey('ask_${entry.askCallId}'),
            entry: entry,
            enabled: !widget.isBusy,
            onSubmit: (answers) => widget.onAnswerAskUser(entry.askCallId!, answers),
          ),
        );

      case OptimizerEntryKind.resultFeedback:
        return _buildResultFeedbackCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.kbDistill:
        return _buildKbDistillRequestCard(l10n, colorScheme);

      case OptimizerEntryKind.notice:
        {
          // The notices that ask the user to do something wear the warning
          // container; the compaction note is information.
          final warn = entry.text == PromptOptimizerAgent.imageMissingNoticeToken ||
              entry.text == PromptOptimizerAgent.kbEntryTooLargeNoticeToken ||
              entry.text == PromptOptimizerAgent.roundLimitNoticeToken;
          final noticeText = switch (entry.text) {
            PromptOptimizerAgent.compactedNoticeToken => l10n.optCompactedNotice,
            PromptOptimizerAgent.imageMissingNoticeToken => l10n.optImageMissing,
            PromptOptimizerAgent.kbEntryTooLargeNoticeToken => l10n.optKbEntryTooLarge,
            PromptOptimizerAgent.roundLimitNoticeToken => l10n.optRoundLimitNotice,
            _ => entry.text,
          };
          return _besideAvatar(
            _avatar(
              warn ? Icons.warning_amber_rounded : Icons.info_outline,
              ground: warn ? semantic.warningContainer : semantic.infoContainer,
              ink: warn ? semantic.warning : semantic.info,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                noticeText,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
            ),
          );
        }

      case OptimizerEntryKind.error:
        // Two cut deliveries in a row stop the turn with their own card: the
        // generic "request failed" would send the user to retry, and a retry
        // is exactly what just failed twice. The fix is the model's cap.
        final truncationStop = entry.text == PromptOptimizerAgent.truncationStopNoticeToken;
        return _besideAvatar(
          _avatar(
            Icons.error_outline,
            ground: colorScheme.errorContainer,
            ink: colorScheme.error,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              // `A3a`: the error at 40% — between the ring and the edge rungs.
              border: Border.all(color: colorScheme.error.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  truncationStop ? l10n.optTruncatedTitle : l10n.optErrorTitle,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: AppSpace.s4),
                SelectableText(
                  truncationStop ? l10n.optTruncatedBody : entry.text,
                  style: textTheme.labelSmall?.mono.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onErrorContainer,
                    height: AppType.proseHeight,
                  ),
                ),
                // The failed turn's context (user message, tool results) is
                // still in the session history — retrying just re-runs the
                // agent turn without re-reading knowledge or images. After a
                // truncation stop the primary action is the setting instead;
                // retry stays, second, for the user who has just raised it.
                if (isLast && !widget.isBusy)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: AppSpace.s10,
                      runSpacing: AppSpace.s6,
                      children: [
                        if (truncationStop && widget.onOpenModelSettings != null)
                          AppButton(
                            label: l10n.optAdjustOutputCap,
                            icon: Icons.tune,
                            variant: AppButtonVariant.destructive,
                            size: AppButtonSize.compact,
                            onPressed: widget.onOpenModelSettings,
                          ),
                        AppButton(
                          label: l10n.optRetry,
                          icon: Icons.refresh,
                          variant: truncationStop && widget.onOpenModelSettings != null
                              ? AppButtonVariant.text
                              : AppButtonVariant.destructive,
                          size: AppButtonSize.compact,
                          onPressed: widget.onRetry,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Knowledge edits
  // ---------------------------------------------------------------------------

}
