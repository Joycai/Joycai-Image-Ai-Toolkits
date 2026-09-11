import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../core/text_diff.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../services/assistant_context_usage.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/llm/context_budget.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_breathing_dot.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_field_size.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/chat_model_selector.dart';
import '../../../widgets/searchable_picker.dart';
import 'optimizer_context_card.dart';

/// The Prompt Assistant's right column (`A3a 1a`, `A3b 1a`/`1b`/`1d`).
///
/// Top to bottom: the refiner model, the three-mode switch, then the mode's
/// own cards — the system prompt; or the knowledge base's status, its write
/// permissions and pending changes (edit mode only), and what this round
/// cited — then the iteration timeline and the context usage in every mode.
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

  /// Every refiner template in the library. Unfiltered: the picker is
  /// searchable — including on the tag, which rides along as each row's badge.
  final List<SystemPrompt> sysPrompts;

  /// True while a turn is queued or running. Puts the knowledge card into its
  /// "reading" state and takes the actions that would disturb the run out of
  /// reach.
  final bool running;

  /// Knowledge edits the agent has staged and the user has not yet answered,
  /// oldest first. Only ever non-empty in [AssistantMode.knowledgeEdit].
  final List<OptimizerChatEntry> pendingKbEdits;

  /// What the agent is currently allowed to do to the knowledge base.
  final KbWritePolicy writePolicy;

  /// Knowledge files the current answer rests on, newest turn first. Passed in
  /// rather than read from the session here, so this panel stays
  /// presentational and testable without the workbench's providers.
  final List<String> citedKnowledgeFiles;

  /// What the session currently spends of the model's window. Measured by the
  /// caller for the same reason as [citedKnowledgeFiles].
  final ContextUsageSnapshot contextUsage;

  /// The session transcript, for the iteration timeline. Passed in whole: the
  /// timeline is a projection of prompt and feedback entries, and the
  /// projection is this panel's presentation concern.
  final List<OptimizerChatEntry> transcript;
  final Function(int?) onModelChanged;
  final Function(String?) onSysPromptChanged;

  /// Loads a template into the editor: its id and its text together.
  final void Function(int? id, String? content) onSysPromptTemplateChanged;

  /// Writes the editor's text back over the template it came from. Owned by
  /// the parent, which is what holds the repository.
  final Future<void> Function(SystemPrompt template, String content) onSaveTemplate;

  /// Answers every staged edit at once — Write all / Discard all.
  final VoidCallback? onWriteAllKbEdits;
  final VoidCallback? onDiscardAllKbEdits;

  /// Persists a change to the three write switches.
  final ValueChanged<KbWritePolicy>? onWritePolicyChanged;

  /// Asks to switch mode. The parent confirms before starting the new session
  /// a switch implies.
  final Function(AssistantMode) onModeChanged;

  /// Creates any missing starter knowledge-base file, picking a folder first
  /// when none is configured. Owned by the parent — this panel stays
  /// presentational.
  final Future<void> Function() onScaffoldKb;

  /// Handed in only by the phone's bottom sheet, which drives the scroll.
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
    this.writePolicy = KbWritePolicy.defaults,
    this.onWriteAllKbEdits,
    this.onDiscardAllKbEdits,
    this.onWritePolicyChanged,
    this.citedKnowledgeFiles = const [],
    this.contextUsage = ContextUsageSnapshot.placeholder,
    this.transcript = const [],
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

  /// Cited files listed before the "All N" figure takes over.
  static const int _citedPreviewCount = 3;

  /// The one gap between every card in this column (`gap:10`).
  static const double _cardGap = AppSpace.s10;

  /// Inside the phone's bottom sheet — the only host that hands a controller —
  /// where `1d` sizes the controls for a finger.
  bool get _touch => widget.scrollController != null;

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
  /// walked during build would drop frames. The count is only ever as fresh as
  /// its last run, which is exactly what the card claims.
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
    final textTheme = Theme.of(context).textTheme;
    final appState = Provider.of<AppState>(context);
    final mode = widget.mode;

    final cards = <Widget>[
      _buildModelCard(l10n, colorScheme, appState),
      _buildModeSelector(l10n),
      if (mode == AssistantMode.systemPrompt)
        _buildSysPromptSection(l10n, colorScheme, textTheme)
      else ...[
        _buildKnowledgeStatus(l10n, colorScheme, textTheme),
        // Directly under the base they govern (`A3b 1a`): which folder, and
        // what may happen to it, are asked together or not at all. The
        // pending list follows the switches that decide whether it exists.
        if (mode == AssistantMode.knowledgeEdit) ...[
          _buildWritePolicy(l10n, colorScheme, textTheme),
          if (widget.pendingKbEdits.isNotEmpty) _buildPendingKbEdits(l10n, colorScheme, textTheme),
        ],
        _buildCitedThisRound(l10n, colorScheme, textTheme),
      ],
      ?_buildIterationTimeline(l10n, colorScheme, textTheme),
      // In every mode: a system-prompt session fills the same window, and a
      // long custom prompt is exactly what fills it unsuspected.
      OptimizerContextCard(usage: widget.contextUsage),
    ];

    // Expanded inside a Column, not a bare SingleChildScrollView: on its own
    // the scroll view shrink-wraps to its content, and the column then
    // shrinks with it. The column claims the height it is offered and lets the
    // body scroll inside it.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: EdgeInsets.all(_touch ? AppSpace.s16 : AppSpace.s10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, card) in cards.indexed) ...[
                  if (index > 0) const SizedBox(height: _cardGap),
                  card,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A picker field as the right column draws one: the column's own ground
  /// inside the theme's hairline box, 32 high (40 in the phone sheet).
  InputDecoration _fieldDecoration(ColorScheme colorScheme) =>
      InputDecoration(filled: true, fillColor: colorScheme.surfaceContainerLow);

  AppFieldSize get _fieldSize => _touch ? AppFieldSize.large : AppFieldSize.regular;

  /// The 11px secondary line every card uses for its notes.
  TextStyle? _noteStyle(ColorScheme colorScheme, TextTheme textTheme) => textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurfaceVariant,
        height: AppType.proseHeight,
      );

  /// Mono 11 — paths, filenames, counts.
  TextStyle? _monoStyle(TextTheme textTheme, Color color) =>
      textTheme.labelSmall?.mono.copyWith(fontWeight: FontWeight.w400, color: color);

  /// A row with a hairline above it and the card's rhythm under that hairline.
  Widget _hairlined(ColorScheme colorScheme, Widget child) => Container(
        padding: const EdgeInsets.only(top: OptimizerPanelCard.gap),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: child,
      );

  Widget _buildModelCard(AppLocalizations l10n, ColorScheme colorScheme, AppState appState) {
    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(l10n.refinerModel),
        ChatModelSelector(
          selectedModelId: widget.selectedModelDbId,
          // The picker dialog's title and glyph; the caption above names the
          // field on the card.
          label: l10n.refinerModel,
          prefixIcon: Icons.tune,
          onChanged: widget.onModelChanged,
          models: appState.multimodalModels,
          size: _fieldSize,
          decoration: _fieldDecoration(colorScheme),
        ),
      ],
    );
  }

  /// The three assistant modes, as the column's top-level navigation.
  ///
  /// No icons and the short edit label on purpose: three segments share the
  /// width of a column that narrows to 250px. The selection wears the accent
  /// wash under the deep ink, as `A3b` draws it.
  Widget _buildModeSelector(AppLocalizations l10n) {
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
      style: AppSegmentStyle.tinted,
    );
  }

  /// `A3b 1b`'s knowledge card: a status badge, then either what the base
  /// holds or what is wrong with it and the way out.
  Widget _buildKnowledgeStatus(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final semantic = context.semantic;
    final status = widget.kbStatus;
    final noteStyle = _noteStyle(colorScheme, textTheme);
    final pathStyle = _monoStyle(textTheme, colorScheme.onSurfaceVariant);

    // Ready / Reading are the accent's — a configured base is a source the
    // agent reads from on every turn, not a finished job. The three faults
    // take the track (nothing chosen yet), the error wash (a folder that is
    // gone) and the warning wash (a folder missing its entry file).
    final (String label, Color background, Color foreground) = switch (status) {
      KbStatus.ok => (
          widget.running ? l10n.optKbSearching : l10n.optKbReady,
          colorScheme.accentTint,
          colorScheme.onAccentTint,
        ),
      KbStatus.notSet => (l10n.notSet, colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      KbStatus.missingDir => (l10n.kbInvalidDir, colorScheme.errorContainer, colorScheme.onErrorContainer),
      KbStatus.missingEntry => (
          l10n.optKbEntryMissingShort(KnowledgeBaseService.entryFileName),
          semantic.warningContainer,
          semantic.onWarningContainer,
        ),
    };
    final badge = OptimizerTagBadge(
      label: label,
      background: background,
      foreground: foreground,
      leading: status == KbStatus.ok
          ? AppBreathingDot(color: colorScheme.primary, size: 6, breathing: widget.running)
          : null,
    );

    if (status != KbStatus.ok) {
      return OptimizerPanelCard(
        children: [
          Align(alignment: AlignmentDirectional.centerStart, child: badge),
          if (status == KbStatus.missingDir && (widget.kbPath ?? '').isNotEmpty)
            _ElidedPath(path: widget.kbPath!, style: pathStyle),
          if (status == KbStatus.missingDir) Text(l10n.optKbPathInvalidDesc, style: noteStyle),
          if (status == KbStatus.notSet) Text(l10n.optKbNotConfigured, style: noteStyle),
          if (status == KbStatus.missingEntry) Text(l10n.kbMissingEntry, style: noteStyle),
          AppButton(
            label: l10n.kbScaffoldCreate,
            // Solid where there is nothing yet, tonal where the folder only
            // needs its entry file, and the quiet form beside a folder that is
            // gone — where initializing is the less likely answer.
            variant: switch (status) {
              KbStatus.notSet => AppButtonVariant.primary,
              KbStatus.missingEntry => AppButtonVariant.tonal,
              _ => AppButtonVariant.secondary,
            },
            accentLabel: true,
            size: _touch ? AppButtonSize.normal : AppButtonSize.compact,
            fullWidth: true,
            loading: _scaffolding,
            onPressed: _handleScaffold,
          ),
        ],
      );
    }

    final stats = _kbStats;
    final updated = stats?.newestModified;

    return OptimizerPanelCard(
      children: [
        Row(
          children: [
            badge,
            const Spacer(),
            // Off during a turn: the agent is reading this folder right now,
            // and a count taken mid-run describes a tree the answer on screen
            // was not built from.
            _TextLink(
              label: l10n.optKbRescan,
              loading: _scanning,
              onTap: widget.running ? null : _loadKbStats,
            ),
          ],
        ),
        _ElidedPath(path: widget.kbPath ?? '', style: pathStyle),
        // Nothing rather than a spinner while there are no counts: a scan that
        // fails would otherwise leave one turning forever. Rescan carries the
        // progress instead, where it resolves.
        //
        // "Content updated", not "last indexed": there is no index. The
        // question the user is asking is whether the edit they just made will
        // be picked up, which the newest file timestamp answers directly.
        if (stats != null) Text(l10n.optKbTreeStats(stats.files, stats.directories), style: noteStyle),
        if (updated != null) Text(l10n.optKbContentUpdated(_formatStamp(updated)), style: noteStyle),
        Wrap(
          spacing: AppSpace.s10,
          runSpacing: AppSpace.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _TextLink(
              label: l10n.openInFolder,
              onTap: widget.kbPath == null ? null : () => FileUtils.openPath(widget.kbPath!),
            ),
            // Kept visible and disabled once the base has an entry file, rather
            // than hidden: initializing is a one-time act, and an action that
            // silently disappears leaves the user wondering where it went. The
            // tooltip says why it is off. KnowledgeBaseStarter.scaffold refuses
            // independently — this is only the first gate.
            Tooltip(
              message: l10n.kbScaffoldAlreadyInit(KnowledgeBaseService.entryFileName),
              child: AppButton(
                label: l10n.kbScaffoldCreate,
                variant: AppButtonVariant.text,
                size: AppButtonSize.compact,
                onPressed: null,
              ),
            ),
          ],
        ),
      ],
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

  /// The iteration timeline: every prompt version with the feedback rounds
  /// between them, projected from the transcript on each build.
  ///
  /// Null for a session with no versions yet — a timeline card with no story
  /// under its heading is noise. No tap-to-jump (the transcript is a lazy list,
  /// and a control that promises navigation it cannot deliver is worse than
  /// none), and no time column: transcript entries carry no timestamp.
  Widget? _buildIterationTimeline(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final nodes = <(OptimizerEntryKind, String, int?)>[
      for (final e in widget.transcript)
        if (e.kind == OptimizerEntryKind.prompt)
          (e.kind, e.note ?? l10n.optPromptVersionLabel, e.version)
        else if (e.kind == OptimizerEntryKind.resultFeedback)
          (e.kind, e.text, e.version),
    ];
    final versionCount = nodes.where((n) => n.$1 == OptimizerEntryKind.prompt).length;
    if (versionCount == 0) return null;
    final lastVersionIndex = nodes.lastIndexWhere((n) => n.$1 == OptimizerEntryKind.prompt);

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption('${l10n.optTimelineTitle} · ${l10n.optTimelineCount(versionCount)}'),
        for (var i = 0; i < nodes.length; i++)
          _timelineRow(nodes[i], l10n, colorScheme, textTheme, isCurrent: i == lastVersionIndex),
      ],
    );
  }

  /// One node: a 6px dot — the accent for the version on screen, amber for a
  /// feedback round, the muted grey for an older version — and its label.
  Widget _timelineRow(
    (OptimizerEntryKind, String, int?) node,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required bool isCurrent,
  }) {
    final semantic = context.semantic;
    final isVersion = node.$1 == OptimizerEntryKind.prompt;

    final Color dot = !isVersion
        ? semantic.warning
        : (isCurrent ? colorScheme.primary : colorScheme.outline);
    final Color ink = !isVersion
        ? colorScheme.onSurfaceVariant
        : (isCurrent ? colorScheme.onAccentTint : colorScheme.onSurface);
    final label = isVersion
        ? (isCurrent
            ? 'v${node.$3 ?? '?'} · ${l10n.optTimelineCurrent} · ${node.$2}'
            : 'v${node.$3 ?? '?'} · ${node.$2}')
        : '${l10n.optFeedbackShort} · ${node.$2}';

    final row = Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: OptimizerPanelCard.gap),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: ink,
              fontWeight: isCurrent ? FontWeight.w500 : null,
            ),
          ),
        ),
      ],
    );
    // The feedback is the user's own words and routinely longer than a row.
    return isVersion ? row : Tooltip(message: node.$2, child: row);
  }

  /// The documents holding up the answer on screen.
  ///
  /// Derived from the session's own history rather than tracked, so it cannot
  /// drift from what was actually sent — see
  /// [PromptOptimizerAgent.citedKnowledgeFiles].
  Widget _buildCitedThisRound(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final cited = widget.citedKnowledgeFiles;
    final shown = cited.take(_citedPreviewCount).toList();
    final more = cited.length > shown.length;
    final allLabel = Text(
      l10n.optKbCitedAll(cited.length),
      style: textTheme.labelMedium?.copyWith(color: colorScheme.onAccentTint),
    );

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.optKbCitedThisRound,
          // `2 · in progress` while the turn runs: "the answer rests on these
          // documents" and "on these so far" are different claims.
          trailing: widget.running
              ? Text(
                  '${cited.length} · ${l10n.optKbCitedRunning}',
                  style: _monoStyle(textTheme, colorScheme.onAccentTint),
                )
              : (more ? allLabel : null),
        ),
        if (cited.isEmpty)
          Text(
            l10n.optKbCitedNone,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          )
        else
          for (final path in shown)
            Row(
              children: [
                Icon(Icons.description_outlined, size: AppSize.iconSm, color: colorScheme.outline),
                const SizedBox(width: AppSpace.s6),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _monoStyle(textTheme, colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
        // While running the caption carries the progress, so the total that
        // would otherwise sit there moves under the list.
        if (widget.running && more) allLabel,
      ],
    );
  }

  /// `A3b 1a`'s write-permissions card: what the agent may do to the folder.
  ///
  /// Three switches rather than one because they fail differently. The first
  /// withdraws the write tool outright — the model is not offered it, so it
  /// cannot be talked into calling it. The second is the approval gate, and
  /// turning it off is the one setting here that lets LLM-authored text reach
  /// the user's files unread; the amber row under it says so, and only while
  /// it is true. The third is the answer to having turned the second off.
  Widget _buildWritePolicy(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final policy = widget.writePolicy;
    final semantic = context.semantic;

    void update(KbWritePolicy next) => widget.onWritePolicyChanged?.call(next);

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(l10n.kbWritePolicyTitle),
        _policyRow(
          colorScheme,
          textTheme,
          title: l10n.kbWriteAllow,
          value: policy.allowWrites,
          onChanged: (v) => update(policy.copyWith(allowWrites: v)),
        ),
        _hairlined(
          colorScheme,
          _policyRow(
            colorScheme,
            textTheme,
            title: l10n.kbWriteConfirmEach,
            value: policy.confirmEachWrite,
            // Off with writing itself off: nothing can be proposed, so there is
            // nothing to confirm.
            onChanged: policy.allowWrites
                ? (v) => update(policy.copyWith(confirmEachWrite: v))
                : null,
          ),
        ),
        if (policy.allowWrites && !policy.confirmEachWrite)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s6),
            decoration: BoxDecoration(
              color: semantic.warningContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.warning_amber_rounded, size: AppSize.iconSm, color: semantic.warning),
                ),
                const SizedBox(width: AppSpace.s6),
                Expanded(
                  child: Text(
                    l10n.kbWriteNoConfirmWarning,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: semantic.onWarningContainer,
                      height: AppType.proseHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _hairlined(
          colorScheme,
          _policyRow(
            colorScheme,
            textTheme,
            title: l10n.kbWriteBackup,
            value: policy.backupBeforeOverwrite,
            onChanged: policy.allowWrites
                ? (v) => update(policy.copyWith(backupBeforeOverwrite: v))
                : null,
          ),
        ),
      ],
    );
  }

  Widget _policyRow(
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return ConstrainedBox(
      // `1d` gives each switch row a 44px touch band in the phone sheet.
      constraints: BoxConstraints(minHeight: _touch ? AppSize.touch - OptimizerPanelCard.gap : 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: (_touch ? textTheme.bodyMedium : textTheme.bodySmall)?.copyWith(
                color: onChanged == null ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                height: AppType.tightHeight,
              ),
            ),
          ),
          const SizedBox(width: OptimizerPanelCard.gap),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// `A3b 1a`'s pending-changes card: every staged edit in one list, and the
  /// two bulk answers.
  ///
  /// The transcript already carries each edit as its own reviewable card, so
  /// this is deliberately not a second place to review them — it is the count,
  /// the files, and the way out of a queue of six without scrolling back
  /// through six cards to find them.
  Widget _buildPendingKbEdits(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final edits = widget.pendingKbEdits;
    final onWriteAll = widget.running ? null : widget.onWriteAllKbEdits;
    final onDiscardAll = widget.running ? null : widget.onDiscardAllKbEdits;

    final Widget actions = _touch
        // `1d`: two equal 44px buttons across the sheet.
        ? Row(
            children: [
              Expanded(
                child: AppButton(
                  label: l10n.kbEditDiscardAll,
                  variant: AppButtonVariant.destructiveOutline,
                  size: AppButtonSize.large,
                  fullWidth: true,
                  onPressed: onDiscardAll,
                ),
              ),
              const SizedBox(width: OptimizerPanelCard.gap),
              Expanded(
                child: AppButton(
                  label: l10n.kbEditWriteAll,
                  size: AppButtonSize.large,
                  fullWidth: true,
                  onPressed: onWriteAll,
                ),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: AppButton(
                  label: l10n.kbEditDiscardAll,
                  variant: AppButtonVariant.destructiveText,
                  size: AppButtonSize.compact,
                  onPressed: onDiscardAll,
                ),
              ),
              const SizedBox(width: AppSpace.s6),
              Flexible(
                child: AppButton(
                  label: l10n.kbEditWriteAll,
                  size: AppButtonSize.compact,
                  onPressed: onWriteAll,
                ),
              ),
            ],
          );

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.kbEditPendingTitle,
          trailing: Text('${edits.length}', style: _monoStyle(textTheme, colorScheme.onSurfaceVariant)),
        ),
        for (final edit in edits) _buildPendingRow(edit, l10n, colorScheme, textTheme),
        _hairlined(colorScheme, actions),
      ],
    );
  }

  Widget _buildPendingRow(
    OptimizerChatEntry edit,
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final semantic = context.semantic;
    final isCreate = edit.oldContent == null;
    final (added, removed) = _pendingCounts(edit);
    // The line counts ride on the row's tooltip: the column narrows to 250px,
    // and the path and its change kind are what have to survive there.
    final counts = [if (added > 0) '+$added', if (removed > 0) '−$removed'].join(' ');

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: _touch ? AppSize.large - OptimizerPanelCard.gap : 0),
      child: Row(
        children: [
          Icon(
            isCreate ? Icons.note_add_outlined : Icons.edit_document,
            size: AppSize.iconMd,
            color: isCreate ? semantic.success : semantic.info,
          ),
          const SizedBox(width: OptimizerPanelCard.gap),
          Expanded(
            child: _ElidedPath(
              path: edit.targetPath ?? '',
              style: (_touch ? textTheme.bodySmall?.mono : textTheme.labelSmall?.mono)
                  ?.copyWith(fontWeight: FontWeight.w400, color: colorScheme.onSurface),
            ),
          ),
          const SizedBox(width: OptimizerPanelCard.gap),
          OptimizerTagBadge(
            mono: true,
            label: isCreate ? l10n.optKbTreeAdded : l10n.optKbTreeChanged,
            background: isCreate ? semantic.successContainer : semantic.infoContainer,
            foreground: isCreate ? semantic.onSuccessContainer : semantic.onInfoContainer,
          ),
        ],
      ),
    );
    return counts.isEmpty ? row : Tooltip(message: counts, child: row);
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

  /// `A3a 1a`'s system-prompt card: which template is loaded, its text, what
  /// the text costs, the two ways out of an edit, and why this mode makes no
  /// tool calls.
  ///
  /// The text is always on screen, a template is where it starts, and the edit
  /// is a state the card can report and undo.
  Widget _buildSysPromptSection(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final semantic = context.semantic;
    final template = _template;
    final text = widget.selectedSysPrompt ?? '';
    final dirty = template != null && text != template.content;

    return OptimizerPanelCard(
      children: [
        OptimizerPanelCaption(
          l10n.systemPrompt,
          // Amber, not the accent: this is a condition to act on — text that
          // will be lost when another template is loaded over it.
          trailing: dirty
              ? OptimizerTagBadge(
                  label: l10n.optSysPromptUnsaved,
                  background: semantic.warningContainer,
                  foreground: semantic.onWarningContainer,
                )
              : null,
        ),
        _buildTemplatePicker(l10n, colorScheme, template),
        _buildSysPromptEditor(l10n, colorScheme, textTheme),
        _buildSysPromptMeter(l10n, colorScheme, textTheme, text),
        if (template != null) _buildSysPromptActions(l10n, template, text, dirty),
        _hairlined(colorScheme, Text(l10n.optSysPromptNoTools, style: _noteStyle(colorScheme, textTheme))),
      ],
    );
  }

  /// The template row. A [SearchablePickerField]: the tag rides along as each
  /// row's badge and the picker matches on it, so filtering by tag is typing
  /// its name rather than setting a second control first.
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
      size: _fieldSize,
      decoration: _fieldDecoration(colorScheme),
      // A dot: the column narrows to 250px and a spelled-out tag there is a
      // coloured box with no letters left in it.
      badgeStyle: PickerBadge.dot,
    );
  }

  /// The instructions themselves.
  ///
  /// `A3a` gives this the remaining height of the column. Here it is a
  /// minimum-height box inside the column's scroll view instead: the column
  /// scrolls — it has to, since the cards below cannot be pushed off — and a
  /// child that claims the leftover space cannot live in a viewport that has
  /// none to give.
  Widget _buildSysPromptEditor(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final style = textTheme.bodySmall?.copyWith(
      height: AppType.proseHeight,
      color: colorScheme.onSurface,
    );
    return TextField(
      controller: _sysPromptCtrl,
      minLines: 8,
      maxLines: null,
      onChanged: widget.onSysPromptChanged,
      style: style,
      decoration: InputDecoration(
        hintText: l10n.optSysPromptHint,
        hintStyle: style?.copyWith(color: colorScheme.outline),
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.all(AppSpace.s10),
      ),
    );
  }

  /// What the text costs, in the two units the user thinks in.
  ///
  /// The token figure is an estimate and says so with `~`: it is the same
  /// [ContextBudget.charsPerToken] ratio the context card measures against, so
  /// the two numbers on this column cannot disagree about the same prompt.
  Widget _buildSysPromptMeter(
    AppLocalizations l10n,
    ColorScheme colorScheme,
    TextTheme textTheme,
    String text,
  ) {
    final tokens = (text.length / ContextBudget.charsPerToken).round();
    return Text(
      '${l10n.optSysPromptChars(text.length)} · ${l10n.optSysPromptTokens(_formatCount(tokens))}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _monoStyle(textTheme, colorScheme.onSurfaceVariant),
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
    final size = _touch ? AppButtonSize.normal : AppButtonSize.compact;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          label: l10n.optSysPromptReset,
          variant: AppButtonVariant.text,
          size: size,
          onPressed: dirty
              ? () => widget.onSysPromptTemplateChanged(template.id, template.content)
              : null,
        ),
        const SizedBox(width: AppSpace.s6),
        AppButton(
          label: l10n.optSysPromptSave,
          size: size,
          loading: _savingTemplate,
          onPressed: dirty ? () => _handleSaveTemplate(template, text) : null,
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
  /// the two figures on this column are read off the same scale.
  static String _formatCount(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
}

/// A deep-ink text action with no box — the knowledge card's Rescan and Open
/// in Folder.
///
/// Not a text [AppButton]: that one insets its label 10px, and `A3b 1b` draws
/// these flush with the path and counts beside them.
class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap, this.loading = false});

  final String label;
  final VoidCallback? onTap;

  /// Shows a spinner before the label and takes the action out of reach.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onTap != null && !loading;
    final color = enabled ? colorScheme.accentText : colorScheme.outline;

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                SizedBox.square(
                  dimension: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
                ),
                const SizedBox(width: AppSpace.s6),
              ],
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
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
          // to end somewhere rather than overflow the row.
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}
