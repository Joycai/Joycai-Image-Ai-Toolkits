import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/file_utils.dart';
import '../../../core/text_diff.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../services/assistant/assistant_context_usage.dart';
import '../../../services/assistant/knowledge_base_service.dart';
import '../../../services/llm/context_budget.dart';
import '../../../services/assistant/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../widgets/ui/app_breathing_dot.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_field_size.dart';
import '../../../widgets/ui/app_segmented_control.dart';
import '../../../widgets/ui/app_switch.dart';
import '../../../widgets/models/chat_model_selector.dart';
import '../../../widgets/ui/searchable_picker.dart';
import 'optimizer_context_card.dart';
import 'result_feedback_labels.dart';

part 'optimizer_config/kb_status_card.dart';
part 'optimizer_config/kb_write_cards.dart';
part 'optimizer_config/panel_links.dart';
part 'optimizer_config/sys_prompt_card.dart';
part 'optimizer_config/timeline_card.dart';

/// The Prompt Assistant's right column (`A3a 1a`, `A3b 1a`/`1b`/`1d`).
///
/// Top to bottom (`A3d 4a`): the two-level mode switch, the refiner model,
/// then the mode's own cards — the task preset; or the knowledge base's
/// status, its write permissions and pending changes (maintenance only), and
/// what this round cited — then the iteration timeline and the context usage
/// in every mode.
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

  /// When given, the context card measures itself through [contextUsageOf]
  /// whenever this notifies, instead of showing [contextUsage]: the usage
  /// moves on every request of a turn, and nothing else on the panel does.
  final Listenable? contextUsageListenable;
  final ContextUsageSnapshot Function()? contextUsageOf;

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
    this.contextUsageListenable,
    this.contextUsageOf,
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

  /// Line counts per staged edit id — see [_KbWriteCards._pendingCounts].
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
      _buildModeSelector(l10n, colorScheme, textTheme),
      _buildModelCard(l10n, colorScheme, appState),
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
      if (widget.contextUsageListenable != null && widget.contextUsageOf != null)
        ListenableBuilder(
          listenable: widget.contextUsageListenable!,
          builder: (context, _) => OptimizerContextCard(usage: widget.contextUsageOf!()),
        )
      else
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

  /// The assistant's mode, as two questions rather than three answers
  /// (`A3d 4a`): what it works *from* — a task preset or the knowledge base —
  /// and, for the knowledge base only, what it is used *for*. The three
  /// [AssistantMode] values are unchanged underneath; this is their drawing.
  ///
  /// First in the column: every card below it is decided by it.
  Widget _buildModeSelector(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    final onKnowledge = widget.mode != AssistantMode.systemPrompt;
    // A turn in flight owns the session a switch would replace — the same
    // reason the toolbar takes New session away while one runs.
    final locked = widget.running;
    final basis = AppSegmentedControl<bool>(
      segments: [
        AppSegment(value: false, label: l10n.optModeSystemPrompt, enabled: !locked || !onKnowledge),
        // Open even with no base configured: the segment is how the user
        // finds the card that says what is missing and offers the way out. A
        // greyed segment explained nothing.
        AppSegment(value: true, label: l10n.optModeKnowledge, enabled: !locked || onKnowledge),
      ],
      value: onKnowledge,
      onChanged: (knowledge) => widget.onModeChanged(
        knowledge ? AssistantMode.knowledgeBase : AssistantMode.systemPrompt,
      ),
      expand: true,
      compact: true,
      style: AppSegmentStyle.tinted,
    );
    if (!onKnowledge) return basis;

    // Nothing to use until the base is there; the status card below says so.
    final usable = widget.kbStatus == KbStatus.ok && !locked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        basis,
        const SizedBox(height: AppSpace.s6),
        Row(
          children: [
            Text(l10n.optModeUseFor, style: _noteStyle(colorScheme, textTheme)),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: AppSegmentedControl<AssistantMode>(
                segments: [
                  for (final (mode, label) in [
                    (AssistantMode.knowledgeBase, l10n.optModeKnowledgeWrite),
                    (AssistantMode.knowledgeEdit, l10n.optModeKnowledgeEdit),
                  ])
                    AppSegment(value: mode, label: label, enabled: usable || widget.mode == mode),
                ],
                value: widget.mode,
                onChanged: widget.onModeChanged,
                expand: true,
                compact: true,
                // Raised, not tinted: the accent is spent one level up, and
                // two tinted tracks stacked read as one control with four ends.
                style: AppSegmentStyle.raised,
              ),
            ),
          ],
        ),
        if (locked) ...[
          const SizedBox(height: AppSpace.s4),
          Text(l10n.optModeLocked, style: _noteStyle(colorScheme, textTheme)),
        ],
      ],
    );
  }

  Future<void> _handleScaffold() async {
    setState(() => _scaffolding = true);
    try {
      await widget.onScaffoldKb();
    } finally {
      if (mounted) setState(() => _scaffolding = false);
    }
  }

  Future<void> _handleSaveTemplate(SystemPrompt template, String text) async {
    setState(() => _savingTemplate = true);
    try {
      await widget.onSaveTemplate(template, text);
    } finally {
      if (mounted) setState(() => _savingTemplate = false);
    }
  }
}
