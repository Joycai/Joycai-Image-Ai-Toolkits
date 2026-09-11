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
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_breathing_dot.dart';
import '../../../widgets/app_button.dart';
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

  /// Enter sends; Shift+Enter inserts a newline.
  ///
  /// This is a chat box, and every chat box works this way — the old
  /// Ctrl+Enter meant the most common action needed two hands and was
  /// undiscoverable without the tooltip. Shift+Enter keeps multi-line prompts
  /// possible, and the hint under the field says so.
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

  /// The 26px r6 square that says whose line this is. No avatar on the
  /// user's own turns — the right-aligned bubble already says it.
  Widget _avatar(IconData icon, {required Color ground, required Color ink}) {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: AppSize.iconMd, color: ink),
    );
  }

  /// An avatar with its content beside it, capped at the body width.
  Widget _besideAvatar(Widget avatar, Widget content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: _avatarGap),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _bodyMaxWidth),
              child: content,
            ),
          ),
        ),
      ],
    );
  }

  /// A card that belongs to the assistant's turn, indented under its avatar
  /// so it lines up with the reply text (`A3b · 1a`).
  Widget _underAvatar(Widget card) {
    return Padding(
      padding: const EdgeInsets.only(left: _turnIndent),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _bodyMaxWidth),
          child: card,
        ),
      ),
    );
  }

  /// The transcript card: 1px hairline, r16, the column ground, clipped.
  ///
  /// The [Material] inside is what makes ink visible: a splash paints on the
  /// nearest Material, and without one here it would land on the scaffold
  /// underneath this card's own fill.
  Widget _card({required List<Widget> children, Color? ground, Color? edge}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ground ?? colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: edge ?? colorScheme.outlineVariant),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  /// A card's 40px title bar: accent glyph, then [children], over a hairline.
  ///
  /// A minimum rather than a fixed height, so a header that has to wrap at a
  /// large text scale grows instead of overflowing. The right inset is 8, not
  /// 12, because the trailing element is nearly always a text action or a
  /// button with its own padding.
  Widget _cardHeader({
    required IconData icon,
    Color? iconColor,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: _cardHeaderHeight),
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSize.iconMd, color: iconColor ?? colorScheme.primary),
          const SizedBox(width: 8),
          ...children,
        ],
      ),
    );
  }

  TextStyle? get _cardTitleStyle => Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      );

  TextStyle? get _cardMetaStyle => Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  /// A deep-ink text action — "Show all 8 steps", "Show full text". Smaller
  /// than a compact [AppButton] on purpose: it sits inside a 40px header or
  /// under 12px body text, where a 28px button reads as a second control row.
  Widget _textAction(String label, VoidCallback? onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: onTap == null ? theme.colorScheme.outline : theme.colorScheme.accentText,
          ),
        ),
      ),
    );
  }

  /// `v3`: r4, the accent wash, mono 11/600 in the deep ink.
  Widget _versionBadge(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.mono.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onAccentTint,
        ),
      ),
    );
  }

  /// A status badge on an opaque semantic container — r4, 11/500.
  Widget _statusBadge(String label, {required Color ground, required Color ink}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Agent process
  // ---------------------------------------------------------------------------

  /// The turn in flight, before it has called anything.
  ///
  /// The same card as a timeline rather than a centred spinner: the run is
  /// part of the conversation and belongs in its column, and when the first
  /// tool result lands this card is replaced by a timeline that opens in
  /// exactly the same place.
  Widget _buildRunningCard(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    return _agentProcessCard(
      steps: const [],
      l10n: l10n,
      colorScheme: colorScheme,
      live: true,
      startedAt: session.runStartedAt,
    );
  }

  Widget _buildAgentTimeline(
    _TranscriptRow row,
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    bool live = false,
    DateTime? startedAt,
  }) {
    return _agentProcessCard(
      steps: row.entries,
      groupKey: row.startIndex,
      l10n: l10n,
      colorScheme: colorScheme,
      live: live,
      startedAt: startedAt,
    );
  }

  /// The agent's working-out for one stretch of a turn, as a single card.
  ///
  /// Collapsed by default to a summary plus the first few steps: the
  /// interesting thing is usually *that* it consulted the knowledge base and
  /// how much, not each individual filename.
  Widget _agentProcessCard({
    required List<OptimizerChatEntry> steps,
    required AppLocalizations l10n,
    required ColorScheme colorScheme,
    int? groupKey,
    bool live = false,
    DateTime? startedAt,
  }) {
    final semantic = context.semantic;
    final key = groupKey ?? -1;
    // A running turn opens itself: three of ten steps is a summary of finished
    // work, but of work in progress it is a card that stops updating three
    // lines in.
    final expanded = live || _expandedToolGroups.contains(key);
    final shown = expanded ? steps : steps.take(_collapsedStepCount).toList();
    final canToggle = !live && groupKey != null && steps.length > _collapsedStepCount;

    final images = steps.where((e) => e.toolName == 'view_image').length;
    final docs = steps.where((e) => e.toolName == 'read_knowledge_file').length;
    final detail = [
      if (images > 0) l10n.optAgentStepsImages(images),
      if (docs > 0) l10n.optAgentStepsDocs(docs),
    ].join(' · ');

    void toggle() => setState(() {
          if (!_expandedToolGroups.remove(key)) _expandedToolGroups.add(key);
        });

    return _underAvatar(
      _card(
        children: [
          _cardHeader(
            icon: Icons.account_tree_outlined,
            children: [
              // Title and meta as one run of text, so a narrow card eats the
              // meta first instead of splitting the width between the two.
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: live
                            ? l10n.optAgentStepsRunning
                            : l10n.optAgentSteps(steps.length),
                        style: _cardTitleStyle,
                      ),
                      if (!live && detail.isNotEmpty) ...[
                        const WidgetSpan(child: SizedBox(width: 8)),
                        TextSpan(text: detail, style: _cardMetaStyle),
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Elapsed while running, what was done once finished. Both answer
              // "how much did this cost me", one in the tense still true.
              if (live) ...[
                const SizedBox(width: 8),
                _ElapsedLabel(
                  since: startedAt,
                  style: _cardMetaStyle?.mono.copyWith(fontWeight: FontWeight.w400),
                ),
                const SizedBox(width: 4),
              ],
              if (canToggle) ...[
                const SizedBox(width: 8),
                _textAction(
                  expanded
                      ? l10n.optAgentStepsCollapse
                      : l10n.optAgentStepsExpand(steps.length),
                  toggle,
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final step in shown) _buildToolStep(step, l10n, colorScheme, semantic),
                // The step being worked on now. It has no name yet — a tool
                // entry is appended when its *result* lands, so the call in
                // flight is not in the transcript — which is why this row says
                // only that there is one.
                if (live) _buildWorkingStep(l10n, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Label for one tool call, shared by the timeline card and the lone-call
  /// line so the two cannot describe the same call differently.
  String _toolLabel(OptimizerChatEntry entry, AppLocalizations l10n) {
    return switch (entry.toolName) {
      'view_image' => l10n.optToolViewImage(entry.text),
      'read_knowledge_file' => l10n.optToolReadKnowledge(entry.text),
      'list_knowledge_files' => l10n.optToolListKnowledge,
      // Only reached for restored sessions — a live staged edit renders as an
      // actionable kbEdit card instead.
      'write_knowledge_file' => l10n.optToolWriteKnowledge(entry.text),
      _ => l10n.optToolListImages,
    };
  }

  /// "Working on the next step..." at the foot of a live timeline, behind the
  /// breathing dot — the one loop the design allows.
  Widget _buildWorkingStep(AppLocalizations l10n, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: AppSize.iconSm,
            height: AppSize.iconSm,
            child: Center(child: AppBreathingDot(color: colorScheme.primary)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.optAgentStepWorking,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.accentText,
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
    AppSemanticColors semantic,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.check_rounded, size: AppSize.iconSm, color: semantic.success),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _toolLabel(entry, l10n),
              maxLines: 1,
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

  // ---------------------------------------------------------------------------
  // Entries
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
            child: MarkdownBody(
              data: entry.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                  height: AppType.proseHeight,
                ),
              ),
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
          // The two notices that ask the user to do something wear the warning
          // container; the compaction note is information.
          final warn = entry.text == PromptOptimizerAgent.imageMissingNoticeToken ||
              entry.text == PromptOptimizerAgent.kbEntryTooLargeNoticeToken;
          final noticeText = switch (entry.text) {
            PromptOptimizerAgent.compactedNoticeToken => l10n.optCompactedNotice,
            PromptOptimizerAgent.imageMissingNoticeToken => l10n.optImageMissing,
            PromptOptimizerAgent.kbEntryTooLargeNoticeToken => l10n.optKbEntryTooLarge,
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
                  l10n.optErrorTitle,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: AppSpace.s4),
                SelectableText(
                  entry.text,
                  style: textTheme.labelSmall?.mono.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onErrorContainer,
                    height: AppType.proseHeight,
                  ),
                ),
                // The failed turn's context (user message, tool results) is
                // still in the session history — retrying just re-runs the
                // agent turn without re-reading knowledge or images.
                if (isLast && !widget.isBusy)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: AppButton(
                      label: l10n.optRetry,
                      icon: Icons.refresh,
                      variant: AppButtonVariant.destructive,
                      size: AppButtonSize.compact,
                      onPressed: widget.onRetry,
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

  /// Preview card for a knowledge-base edit the agent proposed. Nothing has
  /// been written yet — this card is the approval gate.
  ///
  /// An update shows a unified diff under the header rather than the design's
  /// "Show content" link alone: on a two-line change inside a long document,
  /// the difference between what the agent was asked to do and what it
  /// actually rewrote is invisible in a wall of new text. A create has no diff
  /// to show and keeps the folded full content, which for a new file is the
  /// same thing.
  Widget _buildKbEditCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final state = entry.editState ?? KbEditState.pending;
    final isCreate = entry.oldContent == null;
    final pending = state == KbEditState.pending;
    final editId = entry.editId!;
    final expanded = _expandedKbEdits.contains(editId);
    final content = entry.newContent ?? '';
    final phone = _phone;
    // A model that truncates its output would silently gut the file; the length
    // drop is the cheapest signal for the most destructive failure mode.
    final suspiciousShrink = !isCreate &&
        entry.oldContent!.length > 200 &&
        content.length < entry.oldContent!.length ~/ 2;

    final (added, removed) =
        isCreate ? (_lineCount(content), 0) : TextDiff.counts(entry.oldContent!, content);

    void toggleContent() => setState(() {
          if (!_expandedKbEdits.remove(editId)) _expandedKbEdits.add(editId);
        });

    return _underAvatar(
      LayoutBuilder(
        builder: (context, box) {
          // Where the card is too narrow for path, badge and link on one line,
          // the link drops to its own row: the path is the only thing in the
          // header that ellipsizing does not make useless, and it has to keep
          // enough room to be read.
          final wide = box.maxWidth >= _kbEditWideHeader;
          final showToggle = _textAction(
            expanded ? l10n.kbEditHide : l10n.kbEditShow(content.length),
            toggleContent,
          );

          return _card(
            children: [
              _cardHeader(
                icon: isCreate ? Icons.note_add_outlined : Icons.edit_document,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.targetPath ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.mono.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Green for a new file, blue for one being changed —
                        // the distinction that matters: a create cannot
                        // destroy anything, an update can.
                        _statusBadge(
                          isCreate ? l10n.kbEditProposedCreate : l10n.kbEditProposedUpdate,
                          ground: isCreate ? semantic.successContainer : semantic.infoContainer,
                          ink: isCreate ? semantic.onSuccessContainer : semantic.onInfoContainer,
                        ),
                      ],
                    ),
                  ),
                  if (!isCreate && (added > 0 || removed > 0)) ...[
                    const SizedBox(width: 8),
                    if (added > 0)
                      Text('+$added',
                          style: textTheme.labelSmall?.mono.copyWith(color: semantic.success)),
                    if (added > 0 && removed > 0) const SizedBox(width: 6),
                    if (removed > 0)
                      Text('−$removed',
                          style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.error)),
                    const SizedBox(width: 4),
                  ],
                  if (isCreate && wide) ...[const SizedBox(width: 8), showToggle],
                ],
              ),
              if (entry.note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text(
                    entry.note!,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                      height: AppType.proseHeight,
                    ),
                  ),
                ),
              if (suspiciousShrink)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: semantic.warningContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.warning_amber_outlined,
                              size: AppSize.iconSm, color: semantic.warning),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.kbEditShrinkWarning(entry.oldContent!.length, content.length),
                            style: textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w400,
                              color: semantic.onWarningContainer,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (isCreate) ...[
                if (!wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 12, 0),
                    child: Align(alignment: Alignment.centerLeft, child: showToggle),
                  ),
                if (expanded) _buildKbEditFullContent(content, colorScheme, textTheme),
              ] else
                _buildKbEditDiff(entry.oldContent!, content, colorScheme, textTheme, semantic),
              if (pending)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: phone
                      ? Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: _phoneActionHeight,
                                child: AppButton(
                                  label: l10n.kbEditReject,
                                  variant: AppButtonVariant.secondary,
                                  fullWidth: true,
                                  onPressed: () => widget.onRejectKbEdit(editId),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: _phoneActionHeight,
                                child: AppButton(
                                  label: l10n.kbEditApply,
                                  variant: AppButtonVariant.tonal,
                                  fullWidth: true,
                                  onPressed: () => widget.onApplyKbEdit(editId),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AppButton(
                              label: l10n.kbEditReject,
                              variant: AppButtonVariant.secondary,
                              size: AppButtonSize.compact,
                              onPressed: () => widget.onRejectKbEdit(editId),
                            ),
                            const SizedBox(width: 6),
                            AppButton(
                              label: l10n.kbEditApply,
                              variant: AppButtonVariant.tonal,
                              size: AppButtonSize.compact,
                              onPressed: () => widget.onApplyKbEdit(editId),
                            ),
                          ],
                        ),
                )
              else
                _buildKbEditResult(state, l10n, colorScheme, textTheme, semantic),
            ],
          );
        },
      ),
    );
  }

  /// What happened to a decided edit, as one 11px line.
  Widget _buildKbEditResult(
    KbEditState state,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSemanticColors semantic,
  ) {
    final (IconData icon, Color glyph, Color ink, String label) = switch (state) {
      KbEditState.applied => (
          Icons.check_circle_outline,
          semantic.success,
          semantic.onSuccessContainer,
          l10n.kbEditApplied,
        ),
      KbEditState.rejected => (
          Icons.cancel_outlined,
          colorScheme.outline,
          colorScheme.onSurfaceVariant,
          l10n.kbEditRejected,
        ),
      _ => (
          Icons.error_outline,
          colorScheme.error,
          colorScheme.onErrorContainer,
          l10n.kbEditFailedShort,
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Icon(icon, size: AppSize.iconSm, color: glyph),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }

  /// The diff body: hunk headers over context, removed and added lines.
  ///
  /// Each line is a full-width band with a coloured left rule — the fill
  /// alone is too pale at 12% to survive being read past, and the rule is
  /// what lets the eye run down the changed region without reading the
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Text(
          AppLocalizations.of(context)!.kbEditNoChange,
          style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
      );
    }

    final mono = textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      height: AppType.proseHeight,
    );

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
                  style: mono?.copyWith(color: colorScheme.outline),
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
  /// proposed file, shown once the header's link is pressed.
  Widget _buildKbEditFullContent(String content, ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      constraints: const BoxConstraints(maxHeight: _kbDiffMaxHeight),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          content,
          style: textTheme.labelSmall?.mono.copyWith(
            fontWeight: FontWeight.w400,
            height: AppType.proseHeight,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  static int _lineCount(String text) {
    if (text.isEmpty) return 0;
    final trimmed = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
    return '\n'.allMatches(trimmed).length + 1;
  }

  // ---------------------------------------------------------------------------
  // Prompt versions
  // ---------------------------------------------------------------------------

  Widget _buildPromptCard(OptimizerChatEntry entry, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    // Keyed by version rather than transcript index: a prompt card is the one
    // row a user scrolls back to, and the version is what identifies it.
    final key = entry.version ?? 1;
    final expanded = _expandedPrompts.contains(key);
    final isLong = entry.text.length > _promptFoldChars;
    final hasFooter = entry.note != null || isLong;

    return _underAvatar(
      _card(
        children: [
          _cardHeader(
            icon: Icons.text_snippet_outlined,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.optPromptTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _cardTitleStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _versionBadge('v${entry.version ?? 1}'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Ghost: a bare glyph inside a card header, no box of its own.
              SizedBox.square(
                dimension: AppSize.compact,
                child: IconButton(
                  icon: const Icon(Icons.content_copy_outlined, size: AppSize.iconMd),
                  tooltip: l10n.optCopy,
                  padding: EdgeInsets.zero,
                  color: colorScheme.onSurfaceVariant,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(AppSize.compact),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.text));
                    AppSnackBar.success(context, l10n.optPromptCopied);
                  },
                ),
              ),
              const SizedBox(width: 6),
              // Tonal: this puts the model's output to work, so it is the
              // accent's — but outranked by the screen's one solid fill.
              AppButton(
                label: l10n.apply,
                variant: AppButtonVariant.tonal,
                size: AppButtonSize.compact,
                onPressed: () => widget.onApplyPrompt(entry.text),
              ),
              const SizedBox(width: 4),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, hasFooter ? 4 : 12),
            // Folded to a readable opening rather than scrolled inside its own
            // box: a long prompt otherwise pushes the reply that explains it,
            // and the composer, off the bottom of the conversation.
            child: _fold(
              MarkdownBody(
                data: entry.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface,
                    height: AppType.looseHeight,
                  ),
                ),
              ),
              folded: isLong && !expanded,
              fadeColor: colorScheme.surfaceContainerLow,
            ),
          ),
          // One footer row: the note and the expand link, in reading order.
          if (hasFooter)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  if (entry.note != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          entry.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colorScheme.onSurfaceVariant,
                            height: AppType.proseHeight,
                          ),
                        ),
                      ),
                    ),
                  if (isLong)
                    _textAction(
                      expanded ? l10n.optPromptCollapse : l10n.optPromptExpand,
                      () => setState(() {
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
  /// `Column` was still being *laid out* inside the cap and reported a huge
  /// RenderFlex overflow for every long prompt. The child has to be given the
  /// unbounded height it wants — which is what [OverflowBox] is for — and the
  /// fixed-height box around it does the hiding. Width constraints are left
  /// null so they pass through untouched and the text wraps as it otherwise
  /// would.
  ///
  /// The fade over the last [_promptFadeHeight] is what tells the reader the
  /// text was cut rather than finished. It is drawn in the card's own fill,
  /// faded from the same colour at zero alpha rather than from
  /// [Colors.transparent], which is transparent *black* and lerps through grey.
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

  // ---------------------------------------------------------------------------
  // Feedback loop (`20b` / `20d`)
  // ---------------------------------------------------------------------------

  /// The generation-feedback turn: the result image's thumbnail, what the
  /// user said about it, and which file and version it reports on.
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
    final monoMeta = textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
    );

    return _besideAvatar(
      _avatar(
        Icons.rate_review_outlined,
        ground: colorScheme.surfaceContainerHigh,
        ink: colorScheme.onSurfaceVariant,
      ),
      _card(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: SizedBox.square(
                    dimension: 44,
                    child: image != null
                        ? Image(image: image.imageProvider, fit: BoxFit.cover)
                        : ColoredBox(
                            color: colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.image_outlined,
                                size: AppSize.iconMd, color: colorScheme.outline),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.optResultFeedbackChatLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.accentText,
                          letterSpacing: AppType.trackedLabelSpacing,
                        ),
                      ),
                      const SizedBox(height: 3),
                      SelectableText(
                        entry.text,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface,
                          height: AppType.looseHeight,
                        ),
                      ),
                      if (imageName != null || entry.version != null) ...[
                        const SizedBox(height: 4),
                        // Separate texts, not one joined string: the file name
                        // is the part that ellipsizes, the version never does.
                        Row(
                          children: [
                            if (imageName != null)
                              Flexible(
                                child: Text(
                                  imageName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: monoMeta,
                                ),
                              ),
                            if (imageName != null && entry.version != null)
                              Text(' · ', style: monoMeta),
                            if (entry.version != null)
                              Text('v${entry.version}', style: monoMeta),
                          ],
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
    );
  }

  /// The distill request. The user pressed a button, so it reads as a turn in
  /// their voice, but the boilerplate instruction it carries is not worth a
  /// bubble of body text. The design's step checklist is deliberately not
  /// drawn — the app does not know those steps, and the real tool timeline
  /// that follows this entry shows what the agent actually did.
  Widget _buildKbDistillRequestCard(AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    return _besideAvatar(
      _avatar(
        Icons.auto_stories_outlined,
        ground: colorScheme.surfaceContainerHigh,
        ink: colorScheme.onSurfaceVariant,
      ),
      _card(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.optDistillAction,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.accentText,
                    letterSpacing: AppType.trackedLabelSpacing,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.optKbDistillRequested,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: AppType.looseHeight,
                  ),
                ),
              ],
            ),
          ),
        ],
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
  /// below later messages with a version badge that no longer matches.
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
    final semantic = context.semantic;

    return _underAvatar(
      _card(
        children: [
          _cardHeader(
            icon: Icons.check_circle_outline,
            iconColor: semantic.success,
            children: [
              Expanded(
                child: Text(
                  l10n.optDistillDoneTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cardTitleStyle,
                ),
              ),
              if (session.promptVersions > 0) ...[
                const SizedBox(width: 8),
                _versionBadge('v${session.promptVersions}'),
                const SizedBox(width: 4),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                            size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            edit.targetPath ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.mono
                                .copyWith(color: colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ..._lineCountBadges(edit, textTheme, semantic, colorScheme),
                        if (edit.note != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              edit.note!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: colorScheme.onSurfaceVariant,
                              ),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                // Tonal, like Apply: it puts the model's output to use.
                child: AppButton(
                  label: l10n.optSaveFinalPrompt,
                  icon: Icons.bookmark_add_outlined,
                  variant: AppButtonVariant.tonal,
                  size: AppButtonSize.compact,
                  onPressed: widget.onSaveFinalPrompt,
                ),
              ),
            ),
        ],
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

  // ---------------------------------------------------------------------------
  // Composer
  // ---------------------------------------------------------------------------

  /// A composer chip: 11px, 2×8, r4, a hairline edge, a 14px glyph.
  Widget _composerChip({
    required IconData icon,
    required String label,
    required Color ink,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSize.iconSm, color: iconColor ?? ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }

  /// The "distill this session" chip (`20d`): deep ink while it can run,
  /// muted with an explanatory tooltip while the session has nothing to
  /// distill yet. A chip rather than a button — it must not outweigh the send
  /// control.
  Widget _buildDistillChip(
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    required bool enabled,
  }) {
    final chip = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: enabled ? widget.onDistill : null,
      child: _composerChip(
        icon: Icons.auto_stories_outlined,
        label: l10n.optDistillAction,
        ink: enabled ? colorScheme.accentText : colorScheme.outline,
        iconColor: enabled ? colorScheme.primary : colorScheme.outline,
      ),
    );
    // The tooltip explains the *disabled* state — the enabled chip's label
    // already says what it does.
    return enabled ? chip : Tooltip(message: l10n.optDistillDisabledTooltip, child: chip);
  }

  /// 32px r10 on the accent (44 r16 on a phone); the track under muted ink
  /// while there is nothing it can do.
  Widget _buildSendButton(
    AppLocalizations l10n,
    ColorScheme colorScheme, {
    required bool enabled,
    required bool phone,
  }) {
    final double side = phone ? AppSize.touch : AppSize.control;
    return SizedBox.square(
      dimension: side,
      child: IconButton(
        icon: const Icon(Icons.arrow_upward_rounded, size: AppSize.iconMd),
        tooltip: l10n.optSend,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.outline,
          minimumSize: Size.square(side),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(phone ? AppRadius.lg : AppRadius.control),
          ),
        ),
        onPressed: enabled ? widget.onSend : null,
      ),
    );
  }

  /// The composer: the text, what goes with it, and how to send or stop it.
  ///
  /// Three rows inside one r16 box: the field; the chips that change what is
  /// sent (reference images, distill) with the run's clock and Stop at the
  /// right; and the keyboard hint beside the send button. The send control is
  /// on a row of its own rather than a suffix, so it does not drift down the
  /// field as the text grows to six lines.
  Widget _buildInputBar(
    PromptOptimizerSession session,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    int maxLines,
  ) {
    final busy = widget.isBusy;
    final canSend = !busy;
    final canStop = busy && widget.onAbort != null;
    final phone = _phone;
    final textTheme = Theme.of(context).textTheme;
    final attachedCount = context.watch<WorkbenchUIState>().optimizerReferenceImages.length;
    // The distill chip (`20d` a/b) rides the composer in knowledge sessions:
    // it sends a turn, so it belongs with the other send control.
    final showDistill = widget.onDistill != null && session.usesKnowledgeBase;
    final canDistill = !busy && session.promptVersions > 0;
    final feedbackCount = session.transcript
        .where((e) => e.kind == OptimizerEntryKind.resultFeedback)
        .length;
    final showChipRow = attachedCount > 0 || showDistill || busy;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: phone ? const EdgeInsets.all(12) : const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _transcriptMaxWidth),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: AppType.proseHeight,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        hintText: busy ? l10n.optChatBusyHint : l10n.optChatHint,
                        hintStyle: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.outline,
                          height: AppType.proseHeight,
                        ),
                        // All four, not just `border`. The app's
                        // InputDecorationTheme sets `enabledBorder` and
                        // `focusedBorder`, and those outrank `border` — so
                        // `border: InputBorder.none` alone left the field's own
                        // outline standing inside the composer box.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (showChipRow) ...[
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // The counter beside the distill chip is the first
                        // thing to go when the box narrows.
                        final showDistillCounts =
                            showDistill && canDistill && constraints.maxWidth >= 560;
                        return Row(
                          children: [
                            // A Wrap, so chips that no longer fit take a second
                            // line instead of pushing Stop out of the box.
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (attachedCount > 0)
                                    _composerChip(
                                      icon: Icons.image_outlined,
                                      label: l10n.optAttachedImages(attachedCount),
                                      // Muted while a turn runs: nothing is
                                      // about to leave with anything.
                                      ink: busy
                                          ? colorScheme.outline
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  if (showDistill)
                                    _buildDistillChip(l10n, colorScheme, enabled: canDistill),
                                  if (showDistillCounts)
                                    Text(
                                      l10n.optDistillCounts(session.promptVersions, feedbackCount),
                                      style: textTheme.labelSmall?.mono.copyWith(
                                        fontWeight: FontWeight.w400,
                                        color: colorScheme.outline,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (busy) ...[
                              const SizedBox(width: 8),
                              _ElapsedLabel(since: session.runStartedAt),
                            ],
                            if (canStop) ...[
                              const SizedBox(width: 8),
                              // Outlined in the error colour, not filled:
                              // stopping is a way out, not the action the
                              // screen is built around.
                              AppButton(
                                label: l10n.optAbort,
                                icon: Icons.stop_circle_outlined,
                                variant: AppButtonVariant.destructiveOutline,
                                size: AppButtonSize.compact,
                                onPressed: widget.onAbort,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          // While running the keyboard hint is about the key
                          // that *stops* it, not the one that sends.
                          canStop ? l10n.optAbortHint : l10n.optSendHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colorScheme.outline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildSendButton(l10n, colorScheme, enabled: canSend, phone: phone),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "12s elapsed" — how long the turn now running has been going.
///
/// Its own widget with its own ticker so that the second hand costs a rebuild
/// of one `Text` rather than of the whole transcript. The session notifies
/// only when a step lands, which on a long knowledge read is tens of seconds
/// apart — a clock rebuilt on those notifications alone would sit frozen for
/// exactly as long as the user most wants to see it move.
class _ElapsedLabel extends StatefulWidget {
  final DateTime? since;

  /// Defaults to mono 11 in the secondary ink.
  final TextStyle? style;

  const _ElapsedLabel({required this.since, this.style});

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
    final theme = Theme.of(context);
    return Text(
      seconds < 60
          ? l10n.optElapsedSeconds(seconds)
          : l10n.optElapsedMinutes(seconds ~/ 60, seconds % 60),
      maxLines: 1,
      style: widget.style ??
          theme.textTheme.labelSmall?.mono.copyWith(
            fontWeight: FontWeight.w400,
            color: theme.colorScheme.onSurfaceVariant,
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
    final textTheme = Theme.of(context).textTheme;
    final state = widget.entry.askState ?? AskUserState.pending;
    if (state != AskUserState.pending) {
      return _buildResolved(state, l10n, colorScheme);
    }
    final canSubmit = widget.enabled && _allAnswered;
    final phone = Responsive.isMobile(context);

    // The 12% wash form: the one card in the transcript that is waiting on
    // the user, so the one that wears the accent.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.accentRing),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, size: AppSize.iconMd, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.optAskUserTitle,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.accentText,
                    ),
                  ),
                ),
              ],
            ),
            for (int i = 0; i < _questions.length; i++) _buildQuestion(i, l10n, colorScheme, textTheme),
            const SizedBox(height: 12),
            if (phone)
              SizedBox(
                height: _PromptOptimizerChatViewState._phoneActionHeight,
                child: AppButton(
                  label: l10n.optAskUserConfirm,
                  fullWidth: true,
                  onPressed: canSubmit ? () => widget.onSubmit(_collectAnswers()) : null,
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: l10n.optAskUserConfirm,
                  size: AppButtonSize.compact,
                  onPressed: canSubmit ? () => widget.onSubmit(_collectAnswers()) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(int qIndex, AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final question = _questions[qIndex];
    final selected = _selections[qIndex] ?? const <int>{};
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  question.header,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: AppType.trackedLabelSpacing,
                  ),
                ),
              ),
              if (question.multiSelect) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.optAskUserMultiHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            question.question,
            style: textTheme.bodyMedium?.copyWith(
              height: AppType.proseHeight,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          for (int o = 0; o < question.options.length; o++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildOption(qIndex, o, question, selected.contains(o), colorScheme, textTheme),
            ),
          _buildOtherField(qIndex, l10n, colorScheme, textTheme),
        ],
      ),
    );
  }

  /// A 32px option row on the panel: hairline at rest, the accent edge and a
  /// filled mark when chosen.
  Widget _buildOption(
    int qIndex,
    int oIndex,
    AskUserQuestion question,
    bool isSelected,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final option = question.options[oIndex];
    final row = Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: BorderSide(color: isSelected ? colorScheme.primary : colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: widget.enabled ? () => _toggleOption(qIndex, oIndex, question.multiSelect) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                _choiceMark(selected: isSelected, multi: question.multiSelect, colorScheme: colorScheme),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.label,
                    style: textTheme.bodySmall?.copyWith(
                      color: widget.enabled ? colorScheme.onSurface : colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final description = option.description;
    return (description == null || description.isEmpty)
        ? row
        : Tooltip(message: description, child: row);
  }

  /// A checkbox for a multi-select question, a radio for a single one.
  Widget _choiceMark({
    required bool selected,
    required bool multi,
    required ColorScheme colorScheme,
  }) {
    final fill = widget.enabled ? colorScheme.primary : colorScheme.outline;
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? fill : null,
        shape: multi ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: multi ? BorderRadius.circular(AppRadius.xs) : null,
        border: selected ? null : Border.all(color: colorScheme.outline, width: 1.5),
      ),
      child: !selected
          ? null
          : multi
              ? Icon(Icons.check_rounded, size: 12, color: colorScheme.onPrimary)
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: colorScheme.onPrimary, shape: BoxShape.circle),
                ),
    );
  }

  /// "Other / add details..." — a free-text row behind a dashed hairline, so
  /// it reads as an optional slot rather than one more option.
  Widget _buildOtherField(int qIndex, AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    return CustomPaint(
      foregroundPainter: _DashedOutlinePainter(
        color: colorScheme.outlineVariant,
        radius: AppRadius.control,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.edit_outlined, size: AppSize.iconSm, color: colorScheme.outline),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _otherCtrls[qIndex],
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: 3,
                  style: textTheme.bodySmall?.copyWith(
                    height: AppType.proseHeight,
                    color: colorScheme.onSurface,
                  ),
                  // setState so the confirm button re-evaluates _allAnswered.
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hintText: l10n.optAskUserOtherHint,
                    hintStyle: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Collapsed rendering once the question is no longer actionable.
  Widget _buildResolved(AskUserState state, AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final answered = state == AskUserState.answered;
    final answers = widget.entry.askAnswers ?? const <AskUserAnswer>[];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                answered ? Icons.check_circle_outline : Icons.remove_circle_outline,
                size: AppSize.iconSm,
                color: answered ? semantic.success : colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  answered ? l10n.optAskUserAnswered : l10n.optAskUserDismissed,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
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
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A 1px dashed rounded-rect edge, which [Border] cannot draw.
class _DashedOutlinePainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedOutlinePainter({required this.color, required this.radius});

  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + _dash < metric.length ? distance + _dash : metric.length;
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
