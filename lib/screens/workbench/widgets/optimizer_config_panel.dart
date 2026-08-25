import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/text_diff.dart';
import '../../../core/file_utils.dart';
import '../../../services/assistant_context_usage.dart';
import '../../../services/llm/context_budget.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_status_badge.dart';
import '../../../widgets/chat_model_selector.dart';
import '../../../widgets/searchable_picker.dart';
import '../../../widgets/app_section_label.dart';
import 'optimizer_context_card.dart';

class OptimizerConfigPanel extends StatefulWidget {
  final int? selectedModelDbId;

  /// The system prompt as it will be sent — the editor's text, which may have
  /// been changed away from the template it was loaded from.
  final String? selectedSysPrompt;

  /// Which library template [selectedSysPrompt] came from, or null.
  final int? sysPromptTemplateId;
  final AssistantMode mode;
  final KbStatus kbStatus;
  final String? kbPath;

  /// Every refiner template in the library. Unfiltered: `10g` draws one
  /// template picker and no tag control, and the picker itself is searchable —
  /// including on the tag, which rides along as each row's badge.
  final List<SystemPrompt> sysPrompts;

  /// True while a turn is queued or running. `10i` puts the knowledge card
  /// into its "reading" state and takes the actions that would disturb the run
  /// out of reach.
  final bool running;

  /// Knowledge edits the agent has staged and the user has not yet answered,
  /// oldest first. Only ever non-empty in [AssistantMode.knowledgeEdit].
  final List<OptimizerChatEntry> pendingKbEdits;

  /// Knowledge files the current answer rests on, newest turn first. Passed in
  /// rather than read from the session here, so this panel stays
  /// presentational and testable without the workbench's providers.
  final List<String> citedKnowledgeFiles;

  /// What the session currently spends of the model's window. Measured by the
  /// caller for the same reason as [citedKnowledgeFiles] — it needs the live
  /// session and the selected model's configured window, neither of which this
  /// panel should reach for itself.
  final ContextUsageSnapshot contextUsage;
  final Function(int?) onModelChanged;
  final Function(String?) onSysPromptChanged;

  /// Loads a template into the editor: its id and its text together.
  final void Function(int? id, String? content) onSysPromptTemplateChanged;

  /// Writes the editor's text back over the template it came from. Owned by
  /// the parent, which is what holds the repository — this panel stays
  /// presentational, like it does for the knowledge scaffold below.
  final Future<void> Function(SystemPrompt template, String content) onSaveTemplate;

  /// Answers every staged edit at once, from `10h`'s 全部写入 / 全部丢弃.
  final VoidCallback? onWriteAllKbEdits;
  final VoidCallback? onDiscardAllKbEdits;
  final Function(AssistantMode) onModeChanged;

  /// Creates any missing starter knowledge-base file, picking a folder first
  /// when none is configured. Owned by the parent — this panel stays
  /// presentational.
  final Future<void> Function() onScaffoldKb;
  final ScrollController? scrollController;

  const OptimizerConfigPanel({
    super.key,
    required this.selectedModelDbId,
    required this.selectedSysPrompt,
    required this.sysPromptTemplateId,
    required this.mode,
    required this.kbStatus,
    this.kbPath,
    required this.sysPrompts,
    this.running = false,
    this.pendingKbEdits = const [],
    this.onWriteAllKbEdits,
    this.onDiscardAllKbEdits,
    this.citedKnowledgeFiles = const [],
    this.contextUsage = ContextUsageSnapshot.placeholder,
    required this.onModelChanged,
    required this.onSysPromptChanged,
    required this.onSysPromptTemplateChanged,
    required this.onSaveTemplate,
    required this.onModeChanged,
    required this.onScaffoldKb,
    this.scrollController,
  });

  @override
  State<OptimizerConfigPanel> createState() => _OptimizerConfigPanelState();
}

class _OptimizerConfigPanelState extends State<OptimizerConfigPanel> {
  late final TextEditingController _sysPromptCtrl;
  bool _scaffolding = false;
  bool _savingTemplate = false;

  /// Line counts per staged edit id — see [_pendingCounts].
  final Map<String, (int, int)> _kbEditCounts = {};

  /// What the knowledge base holds, as of the last scan. Null while scanning
  /// for the first time.
  KbTreeStats? _kbStats;
  bool _scanning = false;

  /// Cited files listed before the "all N" link takes over.
  static const int _citedPreviewCount = 3;

  /// The single gap between every card in this column.
  ///
  /// One constant rather than a `Padding(top:)` grown onto each card as it was
  /// added: the panel had picked up 4, 12 and 16 between neighbours, and the
  /// design draws one rhythm down the whole column.
  static const double _cardGap = 12;

  @override
  void initState() {
    super.initState();
    _sysPromptCtrl = TextEditingController(text: widget.selectedSysPrompt ?? '');
    _loadKbStats();
  }

  @override
  void didUpdateWidget(OptimizerConfigPanel old) {
    super.didUpdateWidget(old);
    // Only when the text changed from the outside — a template load, a reset,
    // a restored session. Assigning on every rebuild would fight the user's
    // caret: `TextEditingController.text=` collapses the selection to the end,
    // so every keystroke would jump the cursor there.
    if (widget.selectedSysPrompt != old.selectedSysPrompt &&
        widget.selectedSysPrompt != _sysPromptCtrl.text) {
      _sysPromptCtrl.text = widget.selectedSysPrompt ?? '';
    }
    // A newly configured or repaired base has different contents to count.
    if (widget.kbPath != old.kbPath || widget.kbStatus != old.kbStatus) {
      _loadKbStats();
    }
  }

  /// Counts the tree off the build path.
  ///
  /// [KnowledgeBaseService.scanTree] is synchronous file IO; a large base
  /// walked during build would drop frames. There is nothing to invalidate
  /// here — the count is only ever as fresh as its last run, which is exactly
  /// what the card claims.
  Future<void> _loadKbStats() async {
    final root = widget.kbPath;
    if (root == null || widget.kbStatus != KbStatus.ok) {
      if (mounted) setState(() => _kbStats = null);
      return;
    }

    setState(() => _scanning = true);
    try {
      final stats = await Future(() => KnowledgeBaseService().scanTree(root));
      if (mounted) setState(() => _kbStats = stats);
    } catch (_) {
      // A folder that vanished mid-scan is already reported by kbStatus; the
      // card simply shows no counts rather than an error of its own.
      if (mounted) setState(() => _kbStats = null);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _sysPromptCtrl.dispose();
    super.dispose();
  }

  /// The library template the editor's text was loaded from, if it is still in
  /// the library.
  SystemPrompt? get _template {
    final id = widget.sysPromptTemplateId;
    if (id == null) return null;
    for (final p in widget.sysPrompts) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildModeSelector(l10n, colorScheme),
        const SizedBox(height: _cardGap),
        ChatModelSelector(
          selectedModelId: widget.selectedModelDbId,
          label: l10n.refinerModel,
          onChanged: widget.onModelChanged,
          models: appState.multimodalModels,
          prefixIcon: Icons.tune,
          style: ChatModelSelectorStyle.card,
        ),
        if (widget.mode == AssistantMode.systemPrompt) ...[
          _buildSysPromptSection(l10n, colorScheme),
          const SizedBox(height: _cardGap),
          // In every mode, not only the knowledge ones the design draws: a
          // system-prompt session fills the same window, and a long custom
          // prompt is exactly the thing that fills it without the user
          // suspecting it.
          OptimizerContextCard(usage: widget.contextUsage, note: l10n.optSysPromptNoTools),
        ] else ...[
          const SizedBox(height: _cardGap),
          _buildKnowledgeStatus(l10n, colorScheme),
          const SizedBox(height: _cardGap),
          OptimizerContextCard(usage: widget.contextUsage),
          const SizedBox(height: _cardGap),
          // Its own card, not a tail on the status card: the base's
          // configuration is fixed for the session while this changes with
          // every answer, and reading them as one block invites the two to be
          // confused for each other.
          _buildCitedThisRound(l10n, colorScheme, Theme.of(context).textTheme),
          // Above the cited list would put a queue of actions between two
          // read-only reports; below it, it is the last thing in the column
          // and the one the user came to the panel to act on.
          if (widget.mode == AssistantMode.knowledgeEdit &&
              widget.pendingKbEdits.isNotEmpty) ...[
            const SizedBox(height: _cardGap),
            _buildPendingKbEdits(l10n, colorScheme, Theme.of(context).textTheme),
          ],
        ],
      ],
    );

    // Expanded inside a Column, not a bare SingleChildScrollView: on its own
    // the scroll view shrink-wraps to its content, and the panel card then
    // shrinks with it and floats in the middle of the canvas. The column
    // claims the full height the card offers and lets the body scroll inside
    // it.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
      ],
    );
  }

  /// The three assistant modes, as the panel's top-level navigation.
  ///
  /// No icons and the short edit label on purpose: three segments share the
  /// width of a panel that narrows to 250px, and a glyph plus five characters
  /// each leaves every one of them ellipsized. The raised style keeps the
  /// accent free for the state *inside* the tab — the ready badge, the cited
  /// files — rather than spending it on the tab strip.
  Widget _buildModeSelector(AppLocalizations l10n, ColorScheme colorScheme) {
    final kbSelectable = widget.kbStatus == KbStatus.ok;
    return AppSegmentedControl<AssistantMode>(
      segments: [
        AppSegment(
          value: AssistantMode.systemPrompt,
          label: l10n.optModeSystemPrompt,
        ),
        AppSegment(
          value: AssistantMode.knowledgeBase,
          label: l10n.optModeKnowledge,
          enabled: kbSelectable || widget.mode == AssistantMode.knowledgeBase,
        ),
        AppSegment(
          value: AssistantMode.knowledgeEdit,
          label: l10n.optModeKnowledgeEditShort,
          enabled: kbSelectable || widget.mode == AssistantMode.knowledgeEdit,
        ),
      ],
      value: widget.mode,
      onChanged: widget.onModeChanged,
      expand: true,
      compact: true,
      style: AppSegmentStyle.raised,
    );
  }

  Widget _buildKnowledgeStatus(AppLocalizations l10n, ColorScheme colorScheme) {
    final ok = widget.kbStatus == KbStatus.ok;
    final textTheme = Theme.of(context).textTheme;

    final String problem;
    switch (widget.kbStatus) {
      case KbStatus.ok:
        problem = '';
      case KbStatus.notSet:
        problem = l10n.optKbNotConfigured;
      case KbStatus.missingDir:
        problem = l10n.kbInvalidDir;
      case KbStatus.missingEntry:
        problem = l10n.kbMissingEntry;
    }

    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.menu_book_outlined : Icons.warning_amber_outlined,
                size: AppSize.iconSm,
                color: ok ? colorScheme.onSurfaceVariant : colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.knowledgeBase, style: textTheme.titleSmall)),
              // `running`, which is the accent-tinted pill with a dot the spec
              // draws here — and the honest reading of the state: a configured
              // base is not a finished job, it is a source the agent reads from
              // on every turn for as long as the mode is on. While a turn is
              // actually in flight the same pill says so, per `10i`.
              if (ok)
                AppStatusBadge(
                  label: widget.running ? l10n.optKbSearching : l10n.optKbReady,
                  kind: AppStatusKind.running,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!ok)
            Text(problem, style: textTheme.bodySmall?.copyWith(color: colorScheme.error))
          else ...[
            // The folder, in a code-ish chip: it is a path, and paths read
            // badly as prose at the end of a wrapped sentence.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: _ElidedPath(
                path: widget.kbPath ?? '',
                style: textTheme.labelSmall?.mono.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _buildTreeStatsLine(l10n, colorScheme, textTheme),
          ],
          const SizedBox(height: 10),
          _buildKbActions(l10n, ok),
        ],
      ),
    );
  }

  /// How much the assistant can see, and how fresh it is.
  ///
  /// Deliberately "content updated", not "last indexed": there is no index.
  /// The service reads the folder on every call, so the only thing that can
  /// be stale is this card — and the question the user is actually asking is
  /// whether the edit they just made will be picked up, which the newest file
  /// timestamp answers directly.
  Widget _buildTreeStatsLine(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final stats = _kbStats;
    // Nothing rather than a spinner while there are no counts. A scan that
    // fails — an unreadable folder, a path that moved — would otherwise leave
    // an indeterminate spinner turning forever, which reads as a hung app
    // when the truth is simply that there is nothing to report. The rescan
    // button carries the progress instead, where it resolves.
    if (stats == null) return const SizedBox.shrink();

    final updated = stats.newestModified;
    final parts = [
      l10n.optKbTreeStats(stats.files, stats.directories),
      if (updated != null) l10n.optKbContentUpdated(_formatStamp(updated)),
    ];

    return Text(
      parts.join(' · '),
      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
    );
  }

  /// `HH:mm` while it is today's date, `MM-DD HH:mm` once it is not — a bare
  /// clock time on a three-day-old file reads as "just now".
  String _formatStamp(DateTime when) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final clock = '${two(when.hour)}:${two(when.minute)}';
    final sameDay = when.year == now.year && when.month == now.month && when.day == now.day;
    return sameDay ? clock : '${two(when.month)}-${two(when.day)} $clock';
  }

  Widget _buildKbActions(AppLocalizations l10n, bool ok) {
    if (_scaffolding) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    // Kept visible and disabled once the base has an entry file, rather than
    // hidden: initializing is a one-time act, and an action that silently
    // disappears leaves the user wondering where it went. The tooltip says
    // why it is off. KnowledgeBaseStarter.scaffold refuses independently —
    // this is only the first gate.
    final initialize = Tooltip(
      message: ok ? l10n.kbScaffoldAlreadyInit(KnowledgeBaseService.entryFileName) : '',
      child: AppButton(
        label: l10n.kbScaffoldCreate,
        icon: Icons.auto_awesome_outlined,
        variant: AppButtonVariant.secondary,
        onPressed: ok ? null : _handleScaffold,
      ),
    );

    if (!ok) return Align(alignment: Alignment.centerLeft, child: initialize);

    // Wrap, not Row: the panel narrows to 250px, and three labelled controls
    // on one line there would each be a few ellipsized characters.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        initialize,
        // Rescan is the live action once the base exists, so it takes the
        // tonal weight while initialize sits spent beside it.
        AppButton(
          label: l10n.optKbRescan,
          icon: Icons.refresh,
          variant: AppButtonVariant.secondary,
          loading: _scanning,
          // Off during a turn, as `10i` draws it: the agent is reading this
          // folder right now, and a count taken mid-run describes a tree the
          // answer on screen was not built from.
          onPressed: widget.running ? null : _loadKbStats,
        ),
        AppIconButton(
          icon: Icons.folder_open_outlined,
          tooltip: l10n.openInFolder,
          onPressed: widget.kbPath == null ? null : () => FileUtils.openPath(widget.kbPath!),
        ),
      ],
    );
  }

  /// The documents holding up the answer on screen.
  ///
  /// Derived from the session's own history rather than tracked, so it cannot
  /// drift from what was actually sent — see
  /// [PromptOptimizerAgent.citedKnowledgeFiles].
  Widget _buildCitedThisRound(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final cited = widget.citedKnowledgeFiles;
    final shown = cited.take(_citedPreviewCount).toList();

    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The tracked caption, not a card title: the spec draws this and the
          // context card's heading as the same small label, and they sit two
          // cards apart in the same column.
          AppSectionLabel(
            l10n.optKbCitedThisRound,
            padding: EdgeInsets.zero,
            // `10i` writes this as `5 / 进行中`: a list that is still being
            // added to reads as a complete one otherwise, and "the answer
            // rests on these four documents" is a different claim from "on
            // these four so far".
            trailing: !widget.running
                ? null
                : Text(
                    '${cited.length} · ${l10n.optKbCitedRunning}',
                    style: textTheme.labelMedium?.mono.copyWith(color: colorScheme.outline),
                  ),
          ),
          const SizedBox(height: 8),
          if (cited.isEmpty)
            Text(
              l10n.optKbCitedNone,
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            )
          else ...[
            for (final path in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 7),
                    Flexible(
                      // Monospace, like every other filename on this screen —
                      // the reference panel's captions and the timeline's step
                      // rows name the same files.
                      child: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.mono.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (cited.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.optKbCitedAll(cited.length),
                  // onAccentTint, not `primary`: at 11.5px this is thin text on
                  // a plain surface, and `primary` lands near the contrast floor
                  // on the warmer seeds. See AppSectionLabel's own note.
                  style: textTheme.labelMedium?.copyWith(color: colorScheme.onAccentTint),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// `10h`'s 待确认改动 card: every staged edit in one list, and the two
  /// bulk answers.
  ///
  /// The transcript already carries each edit as its own reviewable card, so
  /// this is deliberately not a second place to review them — it is the count,
  /// the files, and the way out of a queue of six without scrolling back
  /// through six cards to find them.
  Widget _buildPendingKbEdits(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final semantic = context.semantic;
    final edits = widget.pendingKbEdits;

    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSectionLabel(
            l10n.kbEditPendingTitle,
            padding: EdgeInsets.zero,
            trailing: Text(
              '${edits.length}',
              style: textTheme.labelMedium?.mono.copyWith(
                fontWeight: FontWeight.w600,
                color: semantic.warning,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final edit in edits)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildPendingRow(edit, colorScheme, textTheme, semantic),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.kbEditWriteAll,
                  icon: Icons.save_outlined,
                  variant: AppButtonVariant.tonal,
                  fullWidth: true,
                  onPressed: widget.running ? null : widget.onWriteAllKbEdits,
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: l10n.kbEditDiscardAll,
                variant: AppButtonVariant.secondary,
                onPressed: widget.running ? null : widget.onDiscardAllKbEdits,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingRow(
    OptimizerChatEntry edit,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSemanticColors semantic,
  ) {
    final isCreate = edit.oldContent == null;
    final (added, removed) = _pendingCounts(edit);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          // One glyph rather than the chat card's spelled-out badge: this
          // column narrows to 250px, and the path is what has to survive.
          Icon(
            isCreate ? Icons.note_add_outlined : Icons.edit_note_outlined,
            size: 14,
            color: isCreate ? semantic.success : semantic.warning,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _ElidedPath(
              path: edit.targetPath ?? '',
              style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 7),
          if (added > 0)
            Text('+$added', style: textTheme.labelSmall?.mono.copyWith(color: semantic.success)),
          if (removed > 0) ...[
            const SizedBox(width: 5),
            Text('−$removed', style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.error)),
          ],
        ],
      ),
    );
  }

  /// Line counts for one staged edit, memoized by its id.
  ///
  /// A staged edit is immutable — its content is fixed when the agent proposes
  /// it and only its *state* ever changes — so the cache cannot go stale. It
  /// is worth having because this panel rebuilds on every session
  /// notification, and diffing several documents per rebuild is real work to
  /// redo for an answer that cannot have changed.
  (int, int) _pendingCounts(OptimizerChatEntry edit) {
    final id = edit.editId ?? '';
    final cached = _kbEditCounts[id];
    if (cached != null) return cached;

    final content = edit.newContent ?? '';
    final counts = edit.oldContent == null
        ? (_lineCount(content), 0)
        : TextDiff.counts(edit.oldContent!, content);
    _kbEditCounts[id] = counts;
    return counts;
  }

  static int _lineCount(String text) {
    if (text.isEmpty) return 0;
    final trimmed = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
    return '\n'.allMatches(trimmed).length + 1;
  }

  Future<void> _handleScaffold() async {
    setState(() => _scaffolding = true);
    try {
      await widget.onScaffoldKb();
    } finally {
      if (mounted) setState(() => _scaffolding = false);
    }
  }

  /// `10g`'s system-prompt card: which template is loaded, its text, what the
  /// text costs, and the two ways out of an edit.
  ///
  /// Replaces a 预设/自定义 chip pair over two bare dropdowns. That arrangement
  /// made "preset" and "custom" two different places rather than two states of
  /// one: picking a preset showed its title and never its text, so the
  /// instructions actually being sent to the model were not visible anywhere,
  /// and editing them meant flipping to a mode that started from a blank box.
  /// Here the text is always on screen, a template is where it starts, and the
  /// edit is a state the card can report and undo.
  Widget _buildSysPromptSection(AppLocalizations l10n, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final template = _template;
    final text = widget.selectedSysPrompt ?? '';
    final dirty = template != null && text != template.content;

    return AppCard(
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.notes_outlined, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.systemPrompt, style: textTheme.titleSmall)),
              // Amber, not the accent: this is a condition to act on — text
              // that will be lost when another template is loaded over it —
              // and the accent in this panel means "selected".
              if (dirty) AppStatusBadge(label: l10n.optSysPromptUnsaved, kind: AppStatusKind.warning),
            ],
          ),
          const SizedBox(height: 10),
          _buildTemplatePicker(l10n, colorScheme, template),
          const SizedBox(height: 10),
          _buildSysPromptEditor(l10n, colorScheme),
          const SizedBox(height: 8),
          _buildSysPromptMeter(l10n, colorScheme, textTheme, text),
          if (template != null) ...[
            const SizedBox(height: 10),
            _buildSysPromptActions(l10n, template, text, dirty),
          ],
        ],
      ),
    );
  }

  /// The template row. A [SearchablePickerField] rather than the dropdown pair
  /// it replaces: the tag that used to need its own dropdown rides along as
  /// each row's badge, and the picker matches on it — so filtering by tag is
  /// typing its name rather than setting a second control first.
  Widget _buildTemplatePicker(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    SystemPrompt? template,
  ) {
    return SearchablePickerField<int>(
      selected: template == null
          ? null
          : PickerOption<int>(
              value: template.id!,
              label: template.title,
              badge: template.tags.isEmpty ? null : template.tags.first.name,
              badgeColor: template.tags.isEmpty ? null : Color(template.tags.first.color),
            ),
      optionsBuilder: () => [
        for (final p in widget.sysPrompts)
          if (p.id != null)
            PickerOption<int>(
              value: p.id!,
              label: p.title,
              badge: p.tags.isEmpty ? null : p.tags.first.name,
              badgeColor: p.tags.isEmpty ? null : Color(p.tags.first.color),
            ),
      ],
      onChanged: (id) {
        final picked = widget.sysPrompts.firstWhere((p) => p.id == id);
        widget.onSysPromptTemplateChanged(picked.id, picked.content);
      },
      hint: l10n.optSysPromptNone,
      searchHint: l10n.optSysPromptSearch,
      dialogTitle: l10n.optSysPromptPick,
      dialogIcon: Icons.notes_outlined,
      // The caption inside the field rather than above it: the card already
      // carries a title, and a second label stacked over a 36px row cost more
      // height than the row it names.
      decoration: InputDecoration(labelText: l10n.optSysPromptTemplate),
      // A dot, like the workbench's own channel picker: the panel narrows to
      // 250px and a spelled-out tag there is a coloured box with no letters
      // left in it.
      badgeStyle: PickerBadge.dot,
    );
  }

  /// The instructions themselves.
  ///
  /// `10g` gives this the remaining height of the panel. Here it is a
  /// minimum-height box inside the panel's scroll view instead: the column
  /// this sits in scrolls — it has to, since the context card below it cannot
  /// be pushed off — and a child that claims the leftover space cannot live in
  /// a viewport that has none to give.
  Widget _buildSysPromptEditor(AppLocalizations l10n, ColorScheme colorScheme) {
    return TextField(
      controller: _sysPromptCtrl,
      minLines: 8,
      maxLines: null,
      onChanged: widget.onSysPromptChanged,
      // Monospace, as the spec sets it: this is a written-to-a-machine
      // document with a numbered structure, and proportional text made its
      // indentation stop lining up.
      style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
            height: AppType.proseHeight,
            color: colorScheme.onSurface,
          ),
      decoration: InputDecoration(
        hintText: l10n.optSysPromptHint,
        hintStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
        contentPadding: const EdgeInsets.all(10),
      ),
    );
  }

  /// What the text costs, in the two units the user thinks in.
  ///
  /// The token figure is an estimate and says so with `~`: it is the same
  /// [ContextBudget.charsPerToken] ratio the context card below measures
  /// against, so the two numbers on this panel cannot disagree about the size
  /// of the same prompt.
  Widget _buildSysPromptMeter(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String text,
  ) {
    final tokens = (text.length / ContextBudget.charsPerToken).round();
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.optSysPromptChars(text.length),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          l10n.optSysPromptTokens(_formatCount(tokens)),
          style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Commit the edit to the library, or throw it away.
  ///
  /// Both are off unless there is an edit to act on, so the pair is inert
  /// rather than absent while the text still matches its template — the row
  /// keeps its height and the card does not jump the first time a character is
  /// typed.
  Widget _buildSysPromptActions(
    AppLocalizations l10n,
    SystemPrompt template,
    String text,
    bool dirty,
  ) {
    // Compact, and the reset unlabelled by its glyph: at the 250px this panel
    // narrows to, two full-size labelled buttons overflow the card by ~17px,
    // and of the two it is the destination — 保存 — whose word has to survive.
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: l10n.optSysPromptSave,
            icon: Icons.save_outlined,
            size: AppButtonSize.compact,
            fullWidth: true,
            loading: _savingTemplate,
            onPressed: dirty ? () => _handleSaveTemplate(template, text) : null,
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: l10n.optSysPromptReset,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.compact,
          onPressed: dirty
              ? () => widget.onSysPromptTemplateChanged(template.id, template.content)
              : null,
        ),
      ],
    );
  }

  Future<void> _handleSaveTemplate(SystemPrompt template, String text) async {
    setState(() => _savingTemplate = true);
    try {
      await widget.onSaveTemplate(template, text);
    } finally {
      if (mounted) setState(() => _savingTemplate = false);
    }
  }

  /// `18.2K` past a thousand — the same shape [OptimizerContextCard] uses, so
  /// the two figures on this panel are read off the same scale.
  static String _formatCount(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
}

/// A filesystem path that loses its *head* when it does not fit, never its
/// tail.
///
/// `TextOverflow.ellipsis` cuts the end, which on a path throws away the one
/// segment that identifies it — `D:\github\gemini-prompt-generater\knowl…`
/// tells the user nothing they did not already know, while `…\knowledge` tells
/// them exactly which folder the assistant is reading. Whole segments are
/// dropped rather than characters, so what remains is always a real path
/// fragment.
class _ElidedPath extends StatelessWidget {
  final String path;
  final TextStyle? style;

  const _ElidedPath({required this.path, this.style});

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            maxLines: 1,
            textScaler: scaler,
          )..layout();
          return painter.width;
        }

        var shown = path;
        if (widthOf(shown) > constraints.maxWidth) {
          // Both separators, because the path comes from the host filesystem
          // and a Windows path is displayed unchanged on any platform.
          final segments = path.split(RegExp(r'[/\\]'))..removeWhere((s) => s.isEmpty);
          final separator = path.contains(r'\') ? r'\' : '/';
          // Never below the last segment: past that there is nothing left to
          // shorten, and a bare "…" is worse than an overflowing name.
          for (var keep = segments.length - 1; keep >= 1; keep--) {
            final candidate = '…$separator${segments.sublist(segments.length - keep).join(separator)}';
            shown = candidate;
            if (widthOf(candidate) <= constraints.maxWidth) break;
          }
        }

        return Text(
          shown,
          maxLines: 1,
          // Still set: the final fallback is one very long segment, and it has
          // to end somewhere rather than overflow the chip.
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}
