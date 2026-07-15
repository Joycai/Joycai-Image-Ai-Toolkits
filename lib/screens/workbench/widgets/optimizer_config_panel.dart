import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../models/tag.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/prompt_optimizer_agent.dart';
import '../../../state/app_state.dart';
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

  @override
  void initState() {
    super.initState();
    _customCtrl = TextEditingController(
      text: widget.useCustomSysPrompt ? widget.selectedSysPrompt ?? '' : '',
    );
  }

  @override
  void didUpdateWidget(OptimizerConfigPanel old) {
    super.didUpdateWidget(old);
    // When switching into custom mode, pre-populate with the current sys prompt.
    if (widget.useCustomSysPrompt && !old.useCustomSysPrompt) {
      _customCtrl.text = widget.selectedSysPrompt ?? '';
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
        ),
        if (widget.mode == AssistantMode.systemPrompt)
          _buildSysPromptSection(l10n, colorScheme)
        else
          _buildKnowledgeStatus(l10n, colorScheme),
      ],
    );

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      child: content,
    );
  }

  Widget _buildModeSelector(AppLocalizations l10n, ColorScheme colorScheme) {
    final kbSelectable = widget.kbStatus == KbStatus.ok;
    return AppSegmentedControl<AssistantMode>(
      segments: [
        AppSegment(
          value: AssistantMode.systemPrompt,
          label: l10n.optModeSystemPrompt,
          icon: Icons.tune,
        ),
        AppSegment(
          value: AssistantMode.knowledgeBase,
          label: l10n.optModeKnowledge,
          icon: Icons.menu_book_outlined,
          enabled: kbSelectable || widget.mode == AssistantMode.knowledgeBase,
        ),
        AppSegment(
          value: AssistantMode.knowledgeEdit,
          label: l10n.optModeKnowledgeEdit,
          icon: Icons.edit_note_outlined,
          enabled: kbSelectable || widget.mode == AssistantMode.knowledgeEdit,
        ),
      ],
      value: widget.mode,
      onChanged: widget.onModeChanged,
      expand: true,
      compact: true,
    );
  }

  Widget _buildKnowledgeStatus(AppLocalizations l10n, ColorScheme colorScheme) {
    final ok = widget.kbStatus == KbStatus.ok;
    final String text;
    switch (widget.kbStatus) {
      case KbStatus.ok:
        text = widget.kbPath ?? '';
      case KbStatus.notSet:
        text = l10n.optKbNotConfigured;
      case KbStatus.missingDir:
        text = l10n.kbInvalidDir;
      case KbStatus.missingEntry:
        text = l10n.kbMissingEntry;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ok
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : colorScheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.menu_book_outlined : Icons.warning_amber_outlined,
                  size: 16,
                  color: ok ? colorScheme.primary : colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.knowledgeBase,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: ok ? colorScheme.onSurfaceVariant : colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            // Disabled once the base has an entry file: initializing is a
            // one-time act, and KbStatus.ok means one is already there. Shown
            // disabled rather than hidden so the action stays discoverable and
            // its unavailability is explained. KnowledgeBaseStarter.scaffold
            // refuses independently — this is only the first gate.
            Align(
              alignment: Alignment.centerLeft,
              child: _scaffolding
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Tooltip(
                      message: ok
                          ? l10n.kbScaffoldAlreadyInit(KnowledgeBaseService.entryFileName)
                          : '',
                      child: FilledButton.tonalIcon(
                        onPressed: ok ? null : _handleScaffold,
                        icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                        label: Text(l10n.kbScaffoldCreate, style: const TextStyle(fontSize: 11)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
            ),
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
        border: const OutlineInputBorder(),
        isDense: true,
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
                  Expanded(child: Text(t.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
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
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.selectedSysPrompt,
          isDense: true,
          isExpanded: true,
          onChanged: widget.onSysPromptChanged,
          items: widget.filteredSysPrompts.map((p) => DropdownMenuItem(
            value: p.content,
            child: Text(p.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
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
        hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.all(12),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13),
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
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
