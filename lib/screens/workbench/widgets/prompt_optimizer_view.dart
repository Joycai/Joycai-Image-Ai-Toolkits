import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_snackbar.dart';

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

  /// How wide a turn is allowed to run.
  ///
  /// Asymmetric on purpose, and both well under the column: a user turn is
  /// usually one sentence and reads as an aside, while the reply is prose. Set
  /// equal, the short user line came out as a wide, near-empty slab.
  static const double _userBubbleMaxWidth = 420;
  static const double _replyMaxWidth = 520;

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
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
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
            if (session.isRunning || widget.isBusy) _buildWorkingIndicator(l10n, colorScheme),
            _buildInputBar(l10n, colorScheme, composerLines),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
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

    return ListView.builder(
      controller: _scrollCtrl,
      // 16 horizontal, not the spec's 24: the centre column floors at
      // `kMinCenterWidth` (400), where 48px of gutter is an eighth of the
      // conversation's width.
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final isLast = index == rows.length - 1;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: row.isToolGroup
                  ? _buildAgentTimeline(row, l10n, colorScheme)
                  : _buildEntry(row.entries.first, isLast, l10n, colorScheme),
            ),
          ),
        );
      },
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
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final steps = row.entries;
    final expanded = _expandedToolGroups.contains(row.startIndex);
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
                onTap: toggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      // A tinted plate rather than a bare accent glyph: at 16px
                      // on a white card the outline icon read as an error mark
                      // as often as a tick.
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
                      Text(l10n.optAgentSteps(steps.length), style: textTheme.titleSmall),
                      if (detail.isNotEmpty) ...[
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
                    if (steps.length > _collapsedStepCount)
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onAccentTint, height: 1.5),
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
                p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface, height: 1.4),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onErrorContainer, height: 1.4),
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
  Widget _buildKbEditCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
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

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: pending
              ? colorScheme.accentRing
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
            child: Row(
              children: [
                Icon(
                  isCreate ? Icons.note_add_outlined : Icons.edit_note_outlined,
                  size: 15,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isCreate ? l10n.kbEditProposedCreate : l10n.kbEditProposedUpdate,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.targetPath ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (entry.note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Text(
                entry.note!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (suspiciousShrink)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_outlined, size: 14, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.kbEditShrinkWarning(entry.oldContent!.length, content.length),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          // Collapsed by default: a knowledge file can run to thousands of
          // characters and would bury the rest of the conversation.
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 14, 0),
            child: Row(
              children: [
                // Flexible + ellipsis: the label carries a character count and
                // is translated, so its width is not knowable up front — an
                // unflexed child here would size past a narrow card.
                Flexible(
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      expanded ? _expandedKbEdits.remove(editId) : _expandedKbEdits.add(editId);
                    }),
                    icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 16),
                    label: Text(
                      expanded ? l10n.kbEditHide : l10n.kbEditShow(content.length),
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.metricsOnly,
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    height: 1.45,
                    fontFamily: 'monospace',
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
            child: pending
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: l10n.kbEditReject,
                        variant: AppButtonVariant.text,
                        size: AppButtonSize.compact,
                        onPressed: () => widget.onRejectKbEdit(editId),
                      ),
                      const SizedBox(width: 6),
                      AppButton(
                        label: l10n.kbEditApply,
                        icon: Icons.save_outlined,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.compact,
                        onPressed: () => widget.onApplyKbEdit(editId),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(
                        switch (state) {
                          KbEditState.applied => Icons.check_circle_outline,
                          KbEditState.rejected => Icons.cancel_outlined,
                          _ => Icons.error_outline,
                        },
                        size: 14,
                        color: state == KbEditState.failed
                            ? colorScheme.error
                            : colorScheme.outline,
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
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: state == KbEditState.failed
                                ? colorScheme.error
                                : colorScheme.outline,
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
                    style: textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
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
                  p: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface, height: 1.45),
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

  Widget _buildWorkingIndicator(AppLocalizations l10n, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(
            l10n.optAgentWorking,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// The composer: what will be sent, the text, and how to send it.
  ///
  /// The send control moved out of `suffixIcon` and onto its own footer row.
  /// As a suffix it was vertically centred, so it drifted down the field as
  /// the text grew to six lines, and there was nowhere to say that the
  /// reference images go with the message — which is the one thing about this
  /// box that is not obvious.
  Widget _buildInputBar(AppLocalizations l10n, ColorScheme colorScheme, int maxLines) {
    final canSend = !widget.isBusy;
    final textTheme = Theme.of(context).textTheme;
    final attachedCount = context.watch<WorkbenchUIState>().optimizerReferenceImages.length;

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
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colorScheme.outlineVariant),
              // The spec lifts the composer off the transcript rather than
              // leaving it flush with it — it is the one thing on this screen
              // that is always available, whatever is scrolled above it.
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
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
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: widget.inputCtrl,
                    minLines: 1,
                    maxLines: maxLines,
                    style: textTheme.bodyMedium?.copyWith(height: 1.4),
                    decoration: InputDecoration(
                      hintText: l10n.optChatHint,
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
                    // exactly where the composer must not overflow.
                    final showHint = constraints.maxWidth >= 460;

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
                      child: Row(
                        children: [
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
                                color: colorScheme.accentTint,
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image_outlined, size: 14, color: colorScheme.onAccentTint),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      l10n.optAttachedImages(attachedCount),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelMedium
                                          ?.copyWith(color: colorScheme.onAccentTint),
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
                                      l10n.optSendHint,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelSmall
                                          ?.copyWith(color: colorScheme.outline),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 10),
                          // A 32px circle, sized and shaped explicitly:
                          // Material's own filled icon button is a ~40px
                          // rounded square even at compact density, which
                          // outweighed everything else on the footer row.
                          // Still [IconButton.filled] rather than a hand-rolled
                          // plate, because it is what supplies the disabled
                          // fill/foreground pair.
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
                      fontWeight: FontWeight.bold,
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
                    fontWeight: FontWeight.bold,
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4, color: colorScheme.onSurface),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
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
