import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/text_diff.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/app_status_badge.dart';

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
/// chips, staged prompt versions) with an input bar at the bottom. The
/// heavy lifting happens in [PromptOptimizerAgent]; this widget only observes
/// the session.
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

  /// Card width at which the staged-edit header still fits the path and
  /// both actions on one line. Measured against the *card*, not the
  /// window: the transcript is a column inside a panel that can be
  /// dragged narrow at any screen size.
  static const double _kbEditWideHeader = 440;

  /// How wide a turn is allowed to run.
  ///
  /// Asymmetric on purpose, and both well under the column: a user turn is
  /// usually one sentence and reads as an aside, while the reply is prose. Set
  /// equal, the short user line came out as a wide, near-empty slab.
  static const double _userBubbleMaxWidth = 420;
  static const double _replyMaxWidth = 520;

  /// The spinner that stands in for the timeline's tick while a turn runs —
  /// the same 18px the plate it replaces occupies, so the header does not
  /// change height when the turn finishes.
  static const double _liveGlyphSize = 18;

  /// The bubble corner that points back at its speaker.
  static const Radius _tailRadius = Radius.circular(3);
  static const Radius _bubbleRadius = Radius.circular(AppRadius.lg);

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

  /// Enter sends; Shift+Enter inserts a newline.
  ///
  /// This is a chat box, and every chat box works this way — the old
  /// Ctrl+Enter meant the most common action needed two hands and was
  /// undiscoverable without the tooltip. Shift+Enter keeps multi-line prompts
  /// possible, and the hint under the field now says so.
  bool _isSendKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    return isEnter && !HardwareKeyboard.instance.isShiftPressed;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<WorkbenchUIState>().optimizerSession;
    _attachSession(session);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    // The bottom console can be dragged up until this pane is only a couple
    // of hundred pixels tall. A composer that always reserves six lines then
    // leaves nothing for the conversation and overflows outright, so it is
    // capped against the height actually on offer.
    return LayoutBuilder(
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
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ColorScheme colorScheme) {
    // Scrollable, not just centred: the input bar grows to six lines as the
    // user types, and the console below can be dragged up, so the space left
    // for this can fall below the artwork's own height. A bare Column cannot
    // shrink past its children and would overflow instead.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_fix_high, size: 44, color: colorScheme.outlineVariant),
              const SizedBox(height: 16),
              Text(
                l10n.optEmptyChat,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, height: AppType.looseHeight),
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
    // the trailing timeline card is that turn and takes the live treatment
    // `10i` draws — spinner, elapsed, open, with the step it is working on at
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
      // 16 horizontal, not the spec's 24: the centre column floors at
      // `kMinCenterWidth` (400), where 48px of gutter is an eighth of the
      // conversation's width.
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
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
            constraints: const BoxConstraints(maxWidth: 780),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// The turn in flight, before it has called anything.
  ///
  /// Deliberately the same card as a timeline's header row rather than the
  /// centred spinner this replaced: the run is part of the conversation and
  /// belongs in its column, and when the first tool result lands this card is
  /// replaced by a timeline that opens in exactly the same place.
  Widget _buildRunningCard(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _replyMaxWidth),
        child: AppCard(
          outlined: true,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: _liveGlyphSize,
                height: _liveGlyphSize,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  l10n.optAgentStepsRunning,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              _ElapsedLabel(since: session.runStartedAt),
            ],
          ),
        ),
      ),
    );
  }

  /// The agent's working-out for one stretch of a turn, as a single card.
  ///
  /// Collapsed by default to a summary plus the first few steps: the interesting
  /// thing is usually *that* it consulted the knowledge base and how much, not
  /// each individual filename.
  Widget _buildAgentTimeline(
    _TranscriptRow row,
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    bool live = false,
    DateTime? startedAt,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final steps = row.entries;
    // A running turn opens itself. `10i` draws the timeline expanded while the
    // agent works and lets it collapse once it is done: three of ten steps is
    // a summary of finished work, but of work in progress it is a card that
    // stops updating three lines in.
    final expanded = live || _expandedToolGroups.contains(row.startIndex);
    final shown = expanded ? steps : steps.take(_collapsedStepCount).toList();

    final images = steps.where((e) => e.toolName == 'view_image').length;
    final docs = steps.where((e) => e.toolName == 'read_knowledge_file').length;
    final detail = [
      if (images > 0) l10n.optAgentStepsImages(images),
      if (docs > 0) l10n.optAgentStepsDocs(docs),
    ].join(' · ');

    void toggle() => setState(() {
          if (!_expandedToolGroups.remove(row.startIndex)) {
            _expandedToolGroups.add(row.startIndex);
          }
        });

    // Left-aligned and narrower than the column, like the reply it precedes:
    // this is the agent's working-out, not a full-bleed result card.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _replyMaxWidth),
        child: AppCard(
          outlined: true,
          // Zero, so the hairline between summary and steps can run edge to
          // edge the way the spec draws it.
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The tap target is the summary row alone. On the whole card, a
              // tap anywhere in the step list collapsed the card the user had
              // just opened to read it.
              InkWell(
                // Inert while live: the card is held open on purpose, so a tap
                // that appeared to do nothing would read as a broken control.
                onTap: live ? null : toggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      // A tinted plate rather than a bare accent glyph: at 16px
                      // on a white card the outline icon read as an error mark
                      // as often as a tick. While the turn runs the same slot
                      // carries the spinner `10i` puts there — the tick is a
                      // claim that the work finished.
                      if (live)
                        const SizedBox(
                          width: _liveGlyphSize,
                          height: _liveGlyphSize,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.accentTint,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_rounded, size: 12, color: colorScheme.onAccentTint),
                        ),
                      const SizedBox(width: 9),
                      Text(
                        live ? l10n.optAgentStepsRunning : l10n.optAgentSteps(steps.length),
                        style: textTheme.titleSmall,
                      ),
                      // Elapsed while running, what was done once finished.
                      // Both answer "how much did this cost me", one in the
                      // tense that is still true.
                      if (live) ...[
                        const SizedBox(width: 8),
                        _ElapsedLabel(since: startedAt),
                        const Spacer(),
                      ] else if (detail.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            detail,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (!live)
                        Icon(
                          expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: AppSize.iconMd,
                          color: colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final step in shown) _buildToolStep(step, l10n, colorScheme),
                    // The step being worked on now. It has no name yet — a
                    // tool entry is appended when its *result* lands, so the
                    // call in flight is not in the transcript — which is why
                    // this row says only that there is one. `10i` draws the
                    // in-flight step tinted and spinning at the foot of the
                    // list; this is that row, minus a label the app cannot
                    // honestly fill in.
                    if (live) _buildWorkingStep(l10n, colorScheme),
                    if (!live && steps.length > _collapsedStepCount)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          label: expanded
                              ? l10n.optAgentStepsCollapse
                              : l10n.optAgentStepsExpand(steps.length),
                          variant: AppButtonVariant.text,
                          // Compact, so it reads as the spec's inline link
                          // rather than as a 36px button in a list of 12px rows.
                          size: AppButtonSize.compact,
                          onPressed: toggle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Label and glyph for one tool call, shared by the timeline card and the
  /// lone-call fallback so the two cannot describe the same call differently.
  (String, IconData) _describeTool(OptimizerChatEntry entry, AppLocalizations l10n) {
    switch (entry.toolName) {
      case 'view_image':
        return (l10n.optToolViewImage(entry.text), Icons.visibility_outlined);
      case 'read_knowledge_file':
        return (l10n.optToolReadKnowledge(entry.text), Icons.menu_book_outlined);
      case 'list_knowledge_files':
        return (l10n.optToolListKnowledge, Icons.folder_outlined);
      case 'write_knowledge_file':
        // Only reached for restored sessions — a live staged edit renders as
        // an actionable kbEdit card instead.
        return (l10n.optToolWriteKnowledge(entry.text), Icons.edit_note_outlined);
      default:
        return (l10n.optToolListImages, Icons.checklist_rtl);
    }
  }

  /// The tinted "working on it" row at the foot of a live timeline.
  Widget _buildWorkingStep(AppLocalizations l10n, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.optAgentStepWorking,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onAccentTint,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolStep(
    OptimizerChatEntry entry,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final (label, icon) = _describeTool(entry, l10n);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colorScheme.outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(OptimizerChatEntry entry, bool isLast, AppLocalizations l10n, ColorScheme colorScheme) {
    switch (entry.kind) {
      case OptimizerEntryKind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: _userBubbleMaxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              // The accent wash, not `primaryContainer`. The spec draws the
              // user's own turn as a 12% tint of the seed — at several of the
              // every seed `primaryContainer` is a saturated slab that made
              // every question the user asked the loudest thing on the screen.
              color: colorScheme.accentTint,
              borderRadius: const BorderRadius.only(
                topLeft: _bubbleRadius,
                topRight: _bubbleRadius,
                bottomLeft: _bubbleRadius,
                // Points back at the right edge the bubble is aligned to.
                bottomRight: _tailRadius,
              ),
            ),
            child: SelectableText(
              entry.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onAccentTint, height: AppType.looseHeight),
            ),
          ),
        );

      case OptimizerEntryKind.assistant:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: _replyMaxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: _bubbleRadius,
                topRight: _bubbleRadius,
                bottomRight: _bubbleRadius,
                bottomLeft: _tailRadius,
              ),
            ),
            child: MarkdownBody(
              data: entry.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface, height: AppType.proseHeight),
              ),
            ),
          ),
        );

      case OptimizerEntryKind.tool:
        // Reached only for a lone tool call with no neighbours; a run of them
        // is grouped into the timeline card by _groupRows before this.
        return Align(
          alignment: Alignment.centerLeft,
          child: _buildToolStep(entry, l10n, colorScheme),
        );

      case OptimizerEntryKind.prompt:
        return _buildPromptCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.kbEdit:
        return _buildKbEditCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.askUser:
        // Keyed by call id so the draft selections survive the transcript
        // rebuilds that _resolveKbEdit-style copyWith flips trigger.
        return _AskUserCard(
          key: ValueKey('ask_${entry.askCallId}'),
          entry: entry,
          enabled: !widget.isBusy,
          onSubmit: (answers) => widget.onAnswerAskUser(entry.askCallId!, answers),
        );

      case OptimizerEntryKind.resultFeedback:
        return _buildResultFeedbackCard(entry, l10n, colorScheme);

      case OptimizerEntryKind.kbDistill:
        return _buildKbDistillRequestCard(l10n, colorScheme);

      case OptimizerEntryKind.notice:
        final noticeText = switch (entry.text) {
          PromptOptimizerAgent.compactedNoticeToken => l10n.optCompactedNotice,
          PromptOptimizerAgent.imageMissingNoticeToken => l10n.optImageMissing,
          PromptOptimizerAgent.kbEntryTooLargeNoticeToken => l10n.optKbEntryTooLarge,
          _ => entry.text,
        };
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 13, color: colorScheme.outline),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    noticeText,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        );

      case OptimizerEntryKind.error:
        return Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: _replyMaxWidth),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: _bubbleRadius,
                    topRight: _bubbleRadius,
                    bottomRight: _bubbleRadius,
                    bottomLeft: _tailRadius,
                  ),
                ),
                child: SelectableText(
                  entry.text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onErrorContainer, height: AppType.proseHeight),
                ),
              ),
              // The failed turn's context (user message, tool results) is
              // still in the session history — retrying just re-runs the
              // agent turn without re-reading knowledge or images.
              if (isLast && !widget.isBusy)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AppButton(
                    label: l10n.optRetry,
                    icon: Icons.refresh,
                    variant: AppButtonVariant.secondary,
                    onPressed: widget.onRetry,
                  ),
                ),
            ],
          ),
        );
    }
  }

  /// Preview card for a knowledge-base edit the agent proposed. Nothing has
  /// been written yet — this card is the approval gate.
  ///
  /// `10h` draws it as a unified diff under a header carrying the path and the
  /// `+N −N` counts. It used to offer the whole proposed file behind a "show
  /// 3,140 characters" link, which is not an approval gate: on a two-line
  /// change inside a long document, the difference between what the agent was
  /// asked to do and what it actually rewrote is invisible in a wall of new
  /// text. A create has no diff to show and keeps the folded full content,
  /// which for a new file is the same thing.
  Widget _buildKbEditCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final state = entry.editState ?? KbEditState.pending;
    final isCreate = entry.oldContent == null;
    final pending = state == KbEditState.pending;
    final editId = entry.editId!;
    final expanded = _expandedKbEdits.contains(editId);
    final content = entry.newContent ?? '';
    // A model that truncates its output would silently gut the file; the length
    // drop is the cheapest signal for the most destructive failure mode.
    final suspiciousShrink = !isCreate &&
        entry.oldContent!.length > 200 &&
        content.length < entry.oldContent!.length ~/ 2;

    final (added, removed) =
        isCreate ? (_lineCount(content), 0) : TextDiff.counts(entry.oldContent!, content);

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: pending ? colorScheme.accentRing : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A header band, like the refined-prompt card's: this row carries a
          // path, two counts and two actions, and floating them over the diff
          // left no line between the file's name and its contents.
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            // The identity line and the two actions share a row where there is
            // room and stack where there is not. A single row here overflowed
            // a mobile-width card by ~200px: the badge, a path, two counts and
            // two buttons cannot all give way, and the path is the only one of
            // them that ellipsizing does not make useless.
            child: LayoutBuilder(
              builder: (context, box) {
                final identity = Row(
                  children: [
                    // Green for a new file, amber for one being changed —
                    // `10h`'s own pair, and the distinction that matters: a
                    // create cannot destroy anything, an update can.
                    AppStatusBadge(
                      label: isCreate ? l10n.kbEditProposedCreate : l10n.kbEditProposedUpdate,
                      kind: isCreate ? AppStatusKind.done : AppStatusKind.warning,
                      showDot: false,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.targetPath ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.mono.copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (added > 0)
                      Text('+$added',
                          style: textTheme.labelSmall?.mono.copyWith(color: semantic.success)),
                    if (removed > 0) ...[
                      const SizedBox(width: 6),
                      Text('−$removed',
                          style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.error)),
                    ],
                  ],
                );

                if (!pending) return identity;

                final actions = <Widget>[
                  AppButton(
                    label: l10n.kbEditReject,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.compact,
                    onPressed: () => widget.onRejectKbEdit(editId),
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    label: l10n.kbEditApply,
                    icon: Icons.save_outlined,
                    variant: AppButtonVariant.tonal,
                    size: AppButtonSize.compact,
                    onPressed: () => widget.onApplyKbEdit(editId),
                  ),
                ];

                if (box.maxWidth >= _kbEditWideHeader) {
                  return Row(children: [
                    Expanded(child: identity),
                    const SizedBox(width: 10),
                    ...actions,
                  ]);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    identity,
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                  ],
                );
              },
            ),
          ),
          if (entry.note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                entry.note!,
                style: textTheme.labelMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (suspiciousShrink)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined, size: 14, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.kbEditShrinkWarning(entry.oldContent!.length, content.length),
                      style: textTheme.labelMedium?.copyWith(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          if (isCreate)
            ..._buildKbEditFullContent(entry, l10n, colorScheme, editId, content, expanded)
          else
            _buildKbEditDiff(entry.oldContent!, content, colorScheme, textTheme, semantic),
          if (!pending)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Icon(
                    switch (state) {
                      KbEditState.applied => Icons.check_circle_outline,
                      KbEditState.rejected => Icons.cancel_outlined,
                      _ => Icons.error_outline,
                    },
                    size: 14,
                    color: state == KbEditState.failed ? colorScheme.error : colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      switch (state) {
                        KbEditState.applied => l10n.kbEditApplied,
                        KbEditState.rejected => l10n.kbEditRejected,
                        _ => l10n.kbEditFailedShort,
                      },
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: state == KbEditState.failed ? colorScheme.error : colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The diff body: hunk headers over context, removed and added lines.
  ///
  /// Each line is a full-width band with a coloured left rule, as `10h` draws
  /// it — the fill alone is too pale at 9% to survive being read past, and the
  /// rule is what lets the eye run down the changed region without reading the
  /// `+`/`−` on every line.
  Widget _buildKbEditDiff(
    String oldContent,
    String newContent,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSemanticColors semantic,
  ) {
    final hunks = TextDiff.unified(oldContent, newContent);
    if (hunks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Text(
          AppLocalizations.of(context)!.kbEditNoChange,
          style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final mono = textTheme.labelSmall?.mono.copyWith(height: AppType.proseHeight);

    // Capped and scrollable rather than folded behind a link: a diff is read
    // top to bottom and its first lines are not more important than its last,
    // which is the assumption a fold makes.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _kbDiffMaxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final hunk in hunks) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Text(
                  '@@ -${hunk.oldStart} +${hunk.newStart}',
                  style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                ),
              ),
              for (final line in hunk.lines)
                _buildDiffLine(line, colorScheme, semantic, mono),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiffLine(
    DiffLine line,
    ColorScheme colorScheme,
    AppSemanticColors semantic,
    TextStyle? mono,
  ) {
    final (Color? fill, Color rule, Color ink, String sign) = switch (line.kind) {
      DiffLineKind.added => (
          semantic.success.withValues(alpha: AppAlpha.tint),
          semantic.success,
          semantic.success,
          '+',
        ),
      DiffLineKind.removed => (
          colorScheme.error.withValues(alpha: AppAlpha.tint),
          colorScheme.error,
          colorScheme.error,
          '−',
        ),
      DiffLineKind.context => (null, Colors.transparent, colorScheme.onSurfaceVariant, ' '),
    };

    return Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border(left: BorderSide(color: rule, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Text(
        '$sign ${line.text}',
        maxLines: 1,
        // Clipped, not wrapped: a wrapped diff line loses the one-line-per-line
        // alignment that makes the two sides comparable at a glance.
        overflow: TextOverflow.ellipsis,
        style: mono?.copyWith(color: ink),
      ),
    );
  }

  /// The create case, which has no previous version to diff against: the full
  /// proposed file behind the same show/hide link it always had.
  List<Widget> _buildKbEditFullContent(
    OptimizerChatEntry entry,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    String editId,
    String content,
    bool expanded,
  ) =>
      [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: expanded ? l10n.kbEditHide : l10n.kbEditShow(content.length),
              icon: expanded ? Icons.expand_less : Icons.expand_more,
              variant: AppButtonVariant.text,
              size: AppButtonSize.compact,
              onPressed: () => setState(() {
                if (!_expandedKbEdits.remove(editId)) _expandedKbEdits.add(editId);
              }),
            ),
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxHeight: _kbDiffMaxHeight),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
                      height: AppType.proseHeight,
                      color: colorScheme.onSurface,
                    ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ];

  static int _lineCount(String text) {
    if (text.isEmpty) return 0;
    final trimmed = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
    return '\n'.allMatches(trimmed).length + 1;
  }

  Widget _buildPromptCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    // Keyed by version rather than transcript index: a prompt card is the one
    // row a user scrolls back to, and the version is what identifies it.
    final key = entry.version ?? 1;
    final expanded = _expandedPrompts.contains(key);
    final isLong = entry.text.length > _promptFoldChars;

    // AppCard, not a hand-rolled Container: it already carries `surface`, the
    // `outlineVariant` hairline, `AppRadius.lg` — and `Clip.antiAlias`, which
    // is what keeps the header band's fill inside the rounded top corners.
    //
    // A plain card edge. This border and the heading below it used to be drawn
    // from `tertiary` — a seed-derived hue, so the card that carries the
    // screen's result came out a different colour under each of the seven
    // themes. The spec draws it as an ordinary card with one accent glyph.
    return AppCard(
      outlined: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The header is a band of its own, so the version and the two actions
          // stay legible as a title bar rather than floating on the prompt.
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 15, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(l10n.optPromptTitle, style: textTheme.titleSmall),
                const SizedBox(width: 8),
                // The version as a neutral chip rather than folded into the
                // heading: it identifies the card a user scrolls back to.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    'v${entry.version ?? 1}',
                    style: textTheme.labelSmall?.mono.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                // A boxed icon at the compact rung, not a bare [IconButton]:
                // Material's own is 40px even at compact density, which forced
                // this header taller than the button sitting beside it.
                AppIconButton(
                  icon: Icons.copy_outlined,
                  tooltip: l10n.optCopy,
                  size: AppSize.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.text));
                    AppSnackBar.success(context, l10n.optPromptCopied);
                  },
                ),
                const SizedBox(width: 8),
                // Tonal, the one place in the app that gets it. `8a` calls
                // for it here in the same annotation that makes 应用到工作台
                // the screen's only solid fill: this button is still the
                // accent's — it is what puts the model's output to work — and
                // it is merely outranked. A neutral outline flattened that,
                // leaving it looking like any other button on the card.
                AppButton(
                  label: l10n.apply,
                  icon: Icons.check,
                  variant: AppButtonVariant.tonal,
                  size: AppButtonSize.compact,
                  onPressed: () => widget.onApplyPrompt(entry.text),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            // Folded to a readable opening rather than scrolled inside its own
            // box: a long prompt otherwise pushes the reply that explains it,
            // and the input bar, off the bottom of the conversation.
            child: _fold(
              MarkdownBody(
                data: entry.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface, height: AppType.proseHeight),
                ),
              ),
              folded: isLong && !expanded,
              fadeColor: colorScheme.surface,
            ),
          ),
          // One footer row, not two stacked blocks. The expand control used to
          // sit *above* the note it belonged under, so a long prompt read
          // "…more · why the agent wrote it" in the wrong order.
          if (entry.note != null || isLong)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
              child: Row(
                children: [
                  if (entry.note != null)
                    Expanded(
                      child: Text(
                        entry.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (isLong)
                    AppButton(
                      label: expanded ? l10n.optPromptCollapse : l10n.optPromptExpand,
                      variant: AppButtonVariant.text,
                      size: AppButtonSize.compact,
                      onPressed: () => setState(() {
                        if (!_expandedPrompts.remove(key)) _expandedPrompts.add(key);
                      }),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Shows the first [_promptFoldHeight] of [child] and hides the rest.
  ///
  /// The obvious `ConstrainedBox(maxHeight:) + ClipRect` does not work here and
  /// was the bug: `ClipRect` only clips the painting, so the markdown's inner
  /// `Column` was still being *laid out* inside 260px and reported a 1300px
  /// RenderFlex overflow for every long prompt. The child has to be given the
  /// unbounded height it wants — which is what [OverflowBox] is for — and the
  /// fixed-height box around it does the hiding. Width constraints are left
  /// null so they pass through untouched and the text wraps as it otherwise
  /// would.
  ///
  /// The fade over the last [_promptFadeHeight] is what tells the reader the
  /// text was cut rather than finished — a hard edge mid-sentence reads as a
  /// rendering fault. It is drawn in the card's own fill, faded from the same
  /// colour at zero alpha rather than from [Colors.transparent], which is
  /// transparent *black* and lerps through grey on the way.
  Widget _fold(Widget child, {required bool folded, required Color fadeColor}) {
    if (!folded) return child;
    return Stack(
      children: [
        ClipRect(
          child: SizedBox(
            height: _promptFoldHeight,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _promptFadeHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [fadeColor.withValues(alpha: 0), fadeColor],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The "distill this session" chip (`20d`): accent-tinted while it can run,
  /// neutral with an explanatory tooltip while the session has nothing to
  /// distill yet. A chip rather than a button — it sits beside the attachment
  /// capsule and must not outweigh the send control.
  Widget _buildDistillChip(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required bool enabled,
  }) {
    final chip = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: enabled ? widget.onDistill : null,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: enabled ? colorScheme.accentTint : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: enabled
              ? Border.all(color: colorScheme.primary.withValues(alpha: AppAlpha.ring))
              : Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 13,
              color: enabled ? colorScheme.onAccentTint : colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.optDistillAction,
              style: textTheme.labelMedium?.copyWith(
                color: enabled ? colorScheme.onAccentTint : colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    // The tooltip explains the *disabled* state — the enabled chip's label
    // already says what it does.
    return enabled ? chip : Tooltip(message: l10n.optDistillDisabledTooltip, child: chip);
  }

  /// The generation-feedback turn, `20b`: a user-side card that keeps the
  /// right alignment, accent wash and bottom-right tail of a user bubble, but
  /// wears a header band (icon + label + version chip) and carries the result
  /// image's thumbnail — the two things that make it a report on a specific
  /// version rather than one more instruction.
  Widget _buildResultFeedbackCard(
    OptimizerChatEntry entry,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final imageName = entry.note;
    // Resolved by name against the live reference list: the transcript stores
    // no paths (they must not ship to providers), and the panel already owns
    // the name → image binding. A missing image degrades to a plain glyph.
    final image = imageName == null
        ? null
        : context
            .watch<WorkbenchUIState>()
            .optimizerReferenceImages
            .cast<AppImage?>()
            .firstWhere((i) => i?.name == imageName, orElse: () => null);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: _userBubbleMaxWidth),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorScheme.accentTint,
          borderRadius: const BorderRadius.only(
            topLeft: _bubbleRadius,
            topRight: _bubbleRadius,
            bottomLeft: _bubbleRadius,
            bottomRight: _tailRadius,
          ),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: AppAlpha.ring),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 13, color: colorScheme.onAccentTint),
                  const SizedBox(width: 6),
                  Text(
                    l10n.optResultFeedbackChatLabel,
                    style: textTheme.labelMedium?.copyWith(
                      color: colorScheme.onAccentTint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.version != null) ...[
                    const SizedBox(width: 7),
                    _versionChip('v${entry.version}', colorScheme, accent: true),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: SizedBox(
                      width: 48,
                      height: 60,
                      child: image != null
                          ? Image(image: image.imageProvider, fit: BoxFit.cover)
                          : ColoredBox(
                              color: colorScheme.surfaceContainerHighest,
                              child: Icon(Icons.image_outlined,
                                  size: 18, color: colorScheme.outline),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelectableText(
                          entry.text,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onAccentTint,
                            height: AppType.looseHeight,
                          ),
                        ),
                        if (imageName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            imageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.mono.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The distill request, drawn as a compact user-side pill: the user pressed
  /// a button, so the turn reads in their voice, but the boilerplate
  /// instruction it carries is not worth a bubble of body text. The design's
  /// step checklist ("comparing v1 → v2 → v3…") is deliberately not drawn —
  /// the app does not know those steps, and the real tool timeline that
  /// follows this entry shows what the agent actually did.
  Widget _buildKbDistillRequestCard(AppLocalizations l10n, ColorScheme colorScheme) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: _userBubbleMaxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.accentTint,
          borderRadius: const BorderRadius.only(
            topLeft: _bubbleRadius,
            topRight: _bubbleRadius,
            bottomLeft: _bubbleRadius,
            bottomRight: _tailRadius,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 14, color: colorScheme.onAccentTint),
                const SizedBox(width: 7),
                Text(
                  l10n.optDistillAction,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.onAccentTint,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              l10n.optKbDistillRequested,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: AppType.looseHeight,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// A small mono version capsule — the `v1`/`v2`/`v3` the design threads
  /// through every surface of the feedback loop.
  Widget _versionChip(String text, ColorScheme colorScheme, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: accent
            ? colorScheme.primary.withValues(alpha: AppAlpha.tint)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
              color: accent ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  /// The applied edits of the finished distill turn plus where its wrap-up
  /// card belongs, or null when the card (`20d`·d) has nothing to say: no
  /// distill ran, an edit is still awaiting review, or nothing reached disk.
  /// Derived from the transcript on every build — the card's presence IS the
  /// state, so there is nothing to invalidate.
  ///
  /// [insertBefore] is the transcript index where the distill turn ends — the
  /// next user-initiated entry after it, or the transcript length when the
  /// distill is the latest activity. The card anchors there rather than at the
  /// list tail, so continuing the conversation does not leave it floating
  /// below later messages with a version chip that no longer matches.
  static ({List<OptimizerChatEntry> applied, int insertBefore})? _distillOutcome(
      List<OptimizerChatEntry> transcript) {
    int distillIndex = -1;
    for (var i = transcript.length - 1; i >= 0; i--) {
      if (transcript[i].kind == OptimizerEntryKind.kbDistill) {
        distillIndex = i;
        break;
      }
    }
    if (distillIndex < 0) return null;
    // The distill turn runs until the next user-initiated entry (a typed
    // message, a result-feedback report, or another distill request).
    int boundary = transcript.length;
    for (var i = distillIndex + 1; i < transcript.length; i++) {
      final k = transcript[i].kind;
      if (k == OptimizerEntryKind.user ||
          k == OptimizerEntryKind.resultFeedback ||
          k == OptimizerEntryKind.kbDistill) {
        boundary = i;
        break;
      }
    }
    final applied = <OptimizerChatEntry>[];
    for (var i = distillIndex + 1; i < boundary; i++) {
      final e = transcript[i];
      if (e.kind != OptimizerEntryKind.kbEdit) continue;
      // A pending edit means the review is still open — summarizing now
      // would claim an outcome the user has not decided yet.
      if (e.editState == KbEditState.pending) return null;
      if (e.editState == KbEditState.applied) applied.add(e);
    }
    if (applied.isEmpty) return null;
    return (applied: applied, insertBefore: boundary);
  }

  /// The distill wrap-up card: which files the session's lessons landed in,
  /// with real +/− line counts from the same diff the review cards showed.
  Widget _buildDistillDoneCard(
    PromptOptimizerSession session,
    List<OptimizerChatEntry> applied,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = AppSemanticColors.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: _replyMaxWidth),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: semantic.successContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check, size: 12, color: semantic.onSuccessContainer),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.optDistillDoneTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (session.promptVersions > 0) ...[
                    const SizedBox(width: 8),
                    _versionChip('v${session.promptVersions}', colorScheme),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final edit in applied)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(Icons.description_outlined,
                              size: 13, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              edit.targetPath ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelMedium?.mono
                                  .copyWith(color: colorScheme.onSurface),
                            ),
                          ),
                          const SizedBox(width: 7),
                          ..._lineCountBadges(edit, textTheme, semantic, colorScheme),
                          if (edit.note != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                edit.note!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: textTheme.labelSmall
                                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (widget.onSaveFinalPrompt != null && session.refinedPrompt != null)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: l10n.optSaveFinalPrompt,
                    icon: Icons.bookmark_add_outlined,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.compact,
                    onPressed: widget.onSaveFinalPrompt,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// `+a` / `−r` from the staged edit's own before/after texts — the same
  /// numbers the review card's diff showed, so the wrap-up never claims a
  /// different change than the one that was approved.
  List<Widget> _lineCountBadges(
    OptimizerChatEntry edit,
    TextTheme textTheme,
    AppSemanticColors semantic,
    ColorScheme colorScheme,
  ) {
    final (added, removed) =
        TextDiff.counts(edit.oldContent ?? '', edit.newContent ?? '');
    final style = textTheme.labelSmall?.mono.copyWith(fontWeight: FontWeight.w600);
    return [
      if (added > 0) Text('+$added', style: style?.copyWith(color: semantic.success)),
      if (added > 0 && removed > 0) const SizedBox(width: 4),
      if (removed > 0) Text('−$removed', style: style?.copyWith(color: colorScheme.error)),
    ];
  }

  /// The composer: what will be sent, the text, and how to send it.
  ///
  /// The send control moved out of `suffixIcon` and onto its own footer row.
  /// As a suffix it was vertically centred, so it drifted down the field as
  /// the text grew to six lines, and there was nowhere to say that the
  /// reference images go with the message — which is the one thing about this
  /// box that is not obvious.
  Widget _buildInputBar(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    int maxLines,
  ) {
    final busy = widget.isBusy;
    final canSend = !busy;
    final textTheme = Theme.of(context).textTheme;
    final attachedCount = context.watch<WorkbenchUIState>().optimizerReferenceImages.length;
    // The distill chip (`20d` a/b) rides the composer footer in knowledge
    // sessions: it sends a turn, so it belongs with the other send control.
    final showDistill = widget.onDistill != null && session.usesKnowledgeBase;
    final canDistill = !busy && session.promptVersions > 0;
    final feedbackCount = session.transcript
        .where((e) => e.kind == OptimizerEntryKind.resultFeedback)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Container(
            // A bordered card on `surface`, not a filled grey block. The
            // transcript above is a column of outlined cards; a solid fill
            // here read as one more message rather than as the place the user
            // types, and it was the only input on the screen still wearing the
            // fill the design spec replaced everywhere else.
            decoration: BoxDecoration(
              // Filled and flat while a turn runs, per `10i`: the composer is
              // the one control on this screen that is normally always
              // available, and the whole point of the running state is that
              // for a moment it is not. Lifting it off the page then would say
              // the opposite.
              color: busy ? colorScheme.surfaceContainerHigh : colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colorScheme.outlineVariant),
              // The spec lifts the composer off the transcript rather than
              // leaving it flush with it — it is the one thing on this screen
              // that is always available, whatever is scrolled above it.
              boxShadow: busy ? null : colorScheme.shadowOverlay,
            ),
            // Zero here, with the insets carried by the two children instead:
            // the field's own top padding and the footer's bottom one are not
            // the same number, and a uniform inset on the card flattened that.
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Focus(
                  onKeyEvent: (node, event) {
                    if (canSend && _isSendKey(event)) {
                      widget.onSend();
                      return KeyEventResult.handled;
                    }
                    // Esc stops the turn, which is what the hint under the
                    // field promises while one is running. Scoped to the
                    // composer rather than the screen: that is where the hint
                    // is, and a global Escape binding on the workbench would
                    // fight the dialogs and drawers that already use it.
                    if (busy &&
                        widget.onAbort != null &&
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      widget.onAbort!();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: widget.inputCtrl,
                    minLines: 1,
                    maxLines: maxLines,
                    // Still focusable while busy — `enabled: false` would drop
                    // focus, and the Esc binding above lives on that focus.
                    // What it must not do is accept text that has nowhere to
                    // go until the turn ends.
                    readOnly: busy,
                    style: textTheme.bodyMedium?.copyWith(height: AppType.proseHeight),
                    decoration: InputDecoration(
                      hintText: busy ? l10n.optChatBusyHint : l10n.optChatHint,
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      // All three, not just `border`. The app's
                      // InputDecorationTheme sets `enabledBorder` and
                      // `focusedBorder`, and those outrank `border` — so
                      // `border: InputBorder.none` alone left the field's own
                      // outline standing, drawing a second box inside the
                      // composer card. The spec has one edge here, not two.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(14, 11, 14, 6),
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    // The keyboard hint is the first thing to go: it is a
                    // nicety, while the attachment count changes what gets
                    // sent and the button is the action itself. Below this the
                    // three together do not fit, and a squeezed pane is
                    // exactly where the composer must not overflow. The distill
                    // chip raises the bar — with it in the row, the hint has to
                    // yield sooner — and its own counter goes first of all.
                    final showHint = constraints.maxWidth >= (showDistill ? 560 : 460);
                    final showDistillCounts =
                        showDistill && canDistill && constraints.maxWidth >= 640;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
                      child: Row(
                        children: [
                        if (showDistill) ...[
                          _buildDistillChip(l10n, colorScheme, textTheme, enabled: canDistill),
                          if (showDistillCounts) ...[
                            const SizedBox(width: 8),
                            Text(
                              l10n.optDistillCounts(session.promptVersions, feedbackCount),
                              style: textTheme.labelSmall?.mono
                                  .copyWith(color: colorScheme.outline),
                            ),
                          ],
                          const SizedBox(width: 10),
                        ],
                        if (attachedCount > 0) ...[
                          // Capped, not [Flexible]. Two flex children split the
                          // free space evenly and the unused half of the first
                          // is not handed back — the chip took 168px of its
                          // 235px share and the 67px left over stayed where it
                          // was, pushing the hint and the send button 67px
                          // clear of the card's right edge. Capping it instead
                          // leaves it a non-flexible child that sizes to its
                          // text, so the [Expanded] below owns every pixel
                          // that is actually free.
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.45),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                // The spec's accent capsule: this states what
                                // leaves with the message, which is the one
                                // thing about the composer that is not
                                // obvious, and a badge is one of the three
                                // places accent is allowed.
                                //
                                // Neutral while a turn runs: nothing is about
                                // to leave with anything, so an accent capsule
                                // there is announcing a promise the composer
                                // cannot currently keep.
                                color: busy
                                    ? colorScheme.surfaceContainerHighest
                                    : colorScheme.accentTint,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.image_outlined,
                                    size: 14,
                                    color: busy ? colorScheme.outline : colorScheme.onAccentTint,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      l10n.optAttachedImages(attachedCount),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelMedium?.copyWith(
                                        color: busy ? colorScheme.outline : colorScheme.onAccentTint,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                          Expanded(
                            child: showHint
                                ? Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      // While running the keyboard hint is
                                      // about the key that *stops* it, not the
                                      // one that sends.
                                      busy && widget.onAbort != null
                                          ? l10n.optAbortHint
                                          : l10n.optSendHint,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelSmall
                                          ?.copyWith(color: colorScheme.outline),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 10),
                          if (busy && widget.onAbort != null)
                            // `10i` swaps the send button for a stop control
                            // outlined in the error colour, which is exactly
                            // [AppButtonVariant.destructiveOutline]. Outlined,
                            // not filled: stopping is a way out, not the
                            // action the screen is built around, and a solid
                            // red button on the composer reads as a warning
                            // about the conversation rather than an offer.
                            AppButton(
                              label: l10n.optAbort,
                              icon: Icons.stop_rounded,
                              variant: AppButtonVariant.destructiveOutline,
                              size: AppButtonSize.compact,
                              onPressed: widget.onAbort,
                            )
                          else
                            // A 32px circle, sized and shaped explicitly:
                            // Material's own filled icon button is a ~40px
                            // rounded square even at compact density, which
                            // outweighed everything else on the footer row.
                            // Still [IconButton.filled] rather than a
                            // hand-rolled plate, because it is what supplies
                            // the disabled fill/foreground pair.
                            SizedBox(
                              width: AppSize.iconButton,
                              height: AppSize.iconButton,
                              child: IconButton.filled(
                                icon: const Icon(Icons.send_rounded, size: AppSize.iconMd),
                                tooltip: l10n.optSend,
                                padding: EdgeInsets.zero,
                                style: IconButton.styleFrom(
                                  shape: const CircleBorder(),
                                  minimumSize: const Size.square(AppSize.iconButton),
                                ),
                                onPressed: canSend ? widget.onSend : null,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "已用 12s" — how long the turn now running has been going.
///
/// Its own widget with its own ticker so that the second hand costs a rebuild
/// of one `Text` rather than of the whole transcript. The session notifies
/// only when a step lands, which on a long knowledge read is tens of seconds
/// apart — a clock rebuilt on those notifications alone would sit frozen for
/// exactly as long as the user most wants to see it move.
class _ElapsedLabel extends StatefulWidget {
  final DateTime? since;

  const _ElapsedLabel({required this.since});

  @override
  State<_ElapsedLabel> createState() => _ElapsedLabelState();
}

class _ElapsedLabelState extends State<_ElapsedLabel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since;
    // Nothing rather than "0s" when the start is unknown — a restored session
    // that was left running has a clock with no zero point, and inventing one
    // would report a turn as having just begun when it has been going for
    // however long the app was closed.
    if (since == null) return const SizedBox.shrink();

    final seconds = DateTime.now().difference(since).inSeconds;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      seconds < 60
          ? l10n.optElapsedSeconds(seconds)
          : l10n.optElapsedMinutes(seconds ~/ 60, seconds % 60),
      style: Theme.of(context).textTheme.bodySmall?.mono.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// Structured-question card for a pending `ask_user` tool call.
///
/// Stateful so the draft selections and "other" text live here (keyed by call
/// id in the parent) instead of bloating the chat view's state. Once the
/// entry's state flips to answered/dismissed the card renders collapsed and
/// the draft state is simply never read again.
class _AskUserCard extends StatefulWidget {
  final OptimizerChatEntry entry;

  /// False while an agent turn is queued or running — answering then would
  /// race the self-healing guard, which cancels a still-pending question.
  final bool enabled;
  final void Function(List<AskUserAnswer> answers) onSubmit;

  const _AskUserCard({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  State<_AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<_AskUserCard> {
  /// Selected option indices per question index.
  final Map<int, Set<int>> _selections = {};
  late final List<TextEditingController> _otherCtrls;

  List<AskUserQuestion> get _questions => widget.entry.askQuestions ?? const [];

  @override
  void initState() {
    super.initState();
    _otherCtrls = [for (final _ in _questions) TextEditingController()];
  }

  @override
  void dispose() {
    for (final c in _otherCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isAnswered(int qIndex) =>
      (_selections[qIndex]?.isNotEmpty ?? false) ||
      _otherCtrls[qIndex].text.trim().isNotEmpty;

  bool get _allAnswered {
    for (int i = 0; i < _questions.length; i++) {
      if (!_isAnswered(i)) return false;
    }
    return _questions.isNotEmpty;
  }

  List<AskUserAnswer> _collectAnswers() => [
        for (int i = 0; i < _questions.length; i++)
          AskUserAnswer(
            header: _questions[i].header,
            selected: [
              for (final o in (_selections[i] ?? const <int>{}).toList()..sort())
                _questions[i].options[o].label,
            ],
            otherText: _otherCtrls[i].text.trim().isEmpty ? null : _otherCtrls[i].text.trim(),
          ),
      ];

  void _toggleOption(int qIndex, int oIndex, bool multiSelect) {
    setState(() {
      final current = _selections[qIndex] ?? <int>{};
      if (current.contains(oIndex)) {
        _selections[qIndex] = {...current}..remove(oIndex);
      } else {
        _selections[qIndex] = multiSelect ? {...current, oIndex} : {oIndex};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final state = widget.entry.askState ?? AskUserState.pending;
    if (state != AskUserState.pending) {
      return _buildResolved(state, l10n, colorScheme);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.accentRing),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Row(
              children: [
                Icon(Icons.help_outline, size: 15, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.optAskUserTitle,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (int i = 0; i < _questions.length; i++) _buildQuestion(i, l10n, colorScheme),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: l10n.optAskUserConfirm,
                  icon: Icons.send_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: widget.enabled && _allAnswered
                      ? () => widget.onSubmit(_collectAnswers())
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(int qIndex, AppLocalizations l10n, ColorScheme colorScheme) {
    final question = _questions[qIndex];
    final selected = _selections[qIndex] ?? const <int>{};
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  question.header,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (question.multiSelect) ...[
                const SizedBox(width: 6),
                Text(
                  l10n.optAskUserMultiHint,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            question.question,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: AppType.proseHeight, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (int o = 0; o < question.options.length; o++)
                Tooltip(
                  message: question.options[o].description ?? '',
                  child: FilterChip(
                    label: Text(
                      question.options[o].label,
                      style: Theme.of(context).textTheme.bodySmall?.metricsOnly,
                    ),
                    selected: selected.contains(o),
                    showCheckmark: question.multiSelect,
                    visualDensity: VisualDensity.compact,
                    onSelected: widget.enabled
                        ? (_) => _toggleOption(qIndex, o, question.multiSelect)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _otherCtrls[qIndex],
            enabled: widget.enabled,
            minLines: 1,
            maxLines: 3,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: AppType.proseHeight),
            // setState so the confirm button re-evaluates _allAnswered.
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.optAskUserOtherHint,
              hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsed rendering once the question is no longer actionable.
  Widget _buildResolved(AskUserState state, AppLocalizations l10n, ColorScheme colorScheme) {
    final answers = widget.entry.askAnswers ?? const <AskUserAnswer>[];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                state == AskUserState.answered
                    ? Icons.check_circle_outline
                    : Icons.remove_circle_outline,
                size: 14,
                color: colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  state == AskUserState.answered
                      ? l10n.optAskUserAnswered
                      : l10n.optAskUserDismissed,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
                ),
              ),
            ],
          ),
          for (final answer in answers)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 20),
              child: Text(
                '${answer.header}: '
                '${[...answer.selected, if (answer.otherText != null) answer.otherText!].join(', ')}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
