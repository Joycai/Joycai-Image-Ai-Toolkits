import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../models/tag.dart';
import '../../../core/file_utils.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_segmented_control.dart';
import '../../../widgets/chat_model_selector.dart';
import 'config_section_header.dart';

class OptimizerConfigPanel extends StatefulWidget {
  final int? selectedModelDbId;
  final int? selectedTagId;
  final String? selectedSysPrompt;
  final bool useCustomSysPrompt;
  final AssistantMode mode;
  final KbStatus kbStatus;
  final String? kbPath;
  final List<PromptTag> tags;
  final List<SystemPrompt> filteredSysPrompts;

  /// Knowledge files the current answer rests on, newest turn first. Passed in
  /// rather than read from the session here, so this panel stays
  /// presentational and testable without the workbench's providers.
  final List<String> citedKnowledgeFiles;
  final Function(int?) onModelChanged;
  final Function(int?) onTagChanged;
  final Function(String?) onSysPromptChanged;
  final Function(bool) onUseCustomChanged;
  final Function(AssistantMode) onModeChanged;

  /// Creates any missing starter knowledge-base file, picking a folder first
  /// when none is configured. Owned by the parent — this panel stays
  /// presentational.
  final Future<void> Function() onScaffoldKb;
  final ScrollController? scrollController;

  const OptimizerConfigPanel({
    super.key,
    required this.selectedModelDbId,
    required this.selectedTagId,
    required this.selectedSysPrompt,
    required this.useCustomSysPrompt,
    required this.mode,
    required this.kbStatus,
    this.kbPath,
    required this.tags,
    required this.filteredSysPrompts,
    this.citedKnowledgeFiles = const [],
    required this.onModelChanged,
    required this.onTagChanged,
    required this.onSysPromptChanged,
    required this.onUseCustomChanged,
    required this.onModeChanged,
    required this.onScaffoldKb,
    this.scrollController,
  });

  @override
  State<OptimizerConfigPanel> createState() => _OptimizerConfigPanelState();
}

class _OptimizerConfigPanelState extends State<OptimizerConfigPanel> {
  late final TextEditingController _customCtrl;
  bool _scaffolding = false;

  /// What the knowledge base holds, as of the last scan. Null while scanning
  /// for the first time.
  KbTreeStats? _kbStats;
  bool _scanning = false;

  /// Cited files listed before the "all N" link takes over.
  static const int _citedPreviewCount = 3;

  @override
  void initState() {
    super.initState();
    _customCtrl = TextEditingController(
      text: widget.useCustomSysPrompt ? widget.selectedSysPrompt ?? '' : '',
    );
    _loadKbStats();
  }

  @override
  void didUpdateWidget(OptimizerConfigPanel old) {
    super.didUpdateWidget(old);
    // When switching into custom mode, pre-populate with the current sys prompt.
    if (widget.useCustomSysPrompt && !old.useCustomSysPrompt) {
      _customCtrl.text = widget.selectedSysPrompt ?? '';
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
    _customCtrl.dispose();
    super.dispose();
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
        const SizedBox(height: 4),
        _buildModeSelector(l10n, colorScheme),
        const SizedBox(height: 12),
        ChatModelSelector(
          selectedModelId: widget.selectedModelDbId,
          label: l10n.refinerModel,
          onChanged: widget.onModelChanged,
          models: appState.multimodalModels,
          prefixIcon: Icons.tune,
          style: ChatModelSelectorStyle.card,
        ),
        if (widget.mode == AssistantMode.systemPrompt)
          _buildSysPromptSection(l10n, colorScheme)
        else ...[
          _buildKnowledgeStatus(l10n, colorScheme),
          // Its own card, not a tail on the status card: the base's
          // configuration is fixed for the session while this changes with
          // every answer, and reading them as one block invites the two to be
          // confused for each other.
          _buildCitedThisRound(l10n, colorScheme, Theme.of(context).textTheme),
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

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        outlined: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.menu_book_outlined : Icons.warning_amber_outlined,
                  size: 16,
                  color: ok ? colorScheme.onSurfaceVariant : colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.knowledgeBase, style: textTheme.titleSmall)),
                if (ok) _buildReadyPill(l10n, colorScheme, textTheme),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: _ElidedPath(
                  path: widget.kbPath ?? '',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
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
      ),
    );
  }

  Widget _buildReadyPill(AppLocalizations l10n, ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          l10n.optKbReady,
          style: textTheme.labelMedium?.copyWith(color: colorScheme.primary),
        ),
      ],
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
          onPressed: _loadKbStats,
        ),
        AppIconButton(
          icon: Icons.folder_open_outlined,
          tooltip: l10n.openInFolder,
          size: 34,
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

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        outlined: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.optKbCitedThisRound, style: textTheme.titleSmall),
            const SizedBox(height: 6),
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
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              if (cited.length > shown.length)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.optKbCitedAll(cited.length),
                    style: textTheme.labelMedium?.copyWith(color: colorScheme.primary),
                  ),
                ),
            ],
          ],
        ),
      ),
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

  Widget _buildSysPromptSection(AppLocalizations l10n, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConfigSectionHeader(
          l10n.systemPrompt,
          trailing: _ModeToggle(
            useCustom: widget.useCustomSysPrompt,
            presetLabel: l10n.preset,
            customLabel: l10n.custom,
            onChanged: (useCustom) {
              widget.onUseCustomChanged(useCustom);
              if (!useCustom) {
                // Switching back to preset: clear the effective prompt so the
                // dropdown shows unselected until the user picks one again.
                widget.onSysPromptChanged(null);
              }
            },
          ),
        ),
        const SizedBox(height: 4),
        if (widget.useCustomSysPrompt)
          _buildCustomEditor(l10n, colorScheme)
        else ...[
          _buildTagSelector(l10n, colorScheme),
          const SizedBox(height: 12),
          _buildPresetDropdown(l10n, colorScheme),
        ],
      ],
    );
  }

  Widget _buildTagSelector(AppLocalizations l10n, ColorScheme colorScheme) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.tag,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: widget.selectedTagId,
          isDense: true,
          isExpanded: true,
          onChanged: widget.onTagChanged,
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(l10n.catAll)),
            ...widget.tags.map((t) => DropdownMenuItem<int?>(
              value: t.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(backgroundColor: Color(t.color), radius: 6),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetDropdown(AppLocalizations l10n, ColorScheme colorScheme) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.preset,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.selectedSysPrompt,
          isDense: true,
          isExpanded: true,
          onChanged: widget.onSysPromptChanged,
          items: widget.filteredSysPrompts.map((p) => DropdownMenuItem(
            value: p.content,
            child: Text(p.title, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildCustomEditor(AppLocalizations l10n, ColorScheme colorScheme) {
    return TextField(
      controller: _customCtrl,
      minLines: 4,
      maxLines: null,
      onChanged: widget.onSysPromptChanged,
      decoration: InputDecoration(
        hintText: l10n.customSysPromptHint,
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        contentPadding: const EdgeInsets.all(12),
      ),
      style: Theme.of(context).textTheme.bodyMedium,
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
          // to end somewhere rather than overflow the chip.
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool useCustom;
  final String presetLabel;
  final String customLabel;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({
    required this.useCustom,
    required this.presetLabel,
    required this.customLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Chip(
          label: presetLabel,
          selected: !useCustom,
          onTap: () { if (useCustom) onChanged(false); },
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 4),
        _Chip(
          label: customLabel,
          selected: useCustom,
          onTap: () { if (!useCustom) onChanged(true); },
          colorScheme: colorScheme,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
