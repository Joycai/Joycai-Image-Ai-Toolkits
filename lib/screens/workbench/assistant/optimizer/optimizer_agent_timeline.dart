part of '../prompt_optimizer_view.dart';

/// The running card and the tool-call timeline (`A3a`'s process card).
extension _AgentTimeline on _PromptOptimizerChatViewState {
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
    final shown = expanded
        ? steps
        : steps.take(_PromptOptimizerChatViewState._collapsedStepCount).toList();
    final canToggle =
        !live &&
        groupKey != null &&
        steps.length > _PromptOptimizerChatViewState._collapsedStepCount;

    final images = steps.where((e) => e.toolName == 'view_image').length;
    final docs = steps.where((e) => e.toolName == 'read_knowledge_file').length;
    final detail = [
      if (images > 0) l10n.optAgentStepsImages(images),
      if (docs > 0) l10n.optAgentStepsDocs(docs),
    ].join(' · ');

    void toggle() => _rebuild(() {
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
                        text: live ? l10n.optAgentStepsRunning : l10n.optAgentSteps(steps.length),
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
                  expanded ? l10n.optAgentStepsCollapse : l10n.optAgentStepsExpand(steps.length),
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
  ///
  /// While a tool call streams it counts what has arrived instead. Only this
  /// row listens to that count: it ticks per fragment, and rebuilding the
  /// whole transcript that often is the cost the notifier exists to avoid.
  Widget _buildWorkingStep(AppLocalizations l10n, ColorScheme colorScheme) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.accentText, fontWeight: FontWeight.w500);
    Widget label(int? chars) => Text(
      chars == null || chars <= 0 ? l10n.optAgentStepWorking : l10n.optAgentStepStreaming(chars),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final progress = _session?.streamingToolArgumentChars;

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
            child: progress == null
                ? label(null)
                : ValueListenableBuilder<int?>(
                    valueListenable: progress,
                    builder: (context, chars, _) => label(chars),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Entries
  // ---------------------------------------------------------------------------
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
      style:
          widget.style ??
          theme.textTheme.labelSmall?.mono.copyWith(
            fontWeight: FontWeight.w400,
            color: theme.colorScheme.onSurfaceVariant,
          ),
    );
  }
}
