import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../models/tag.dart';
import '../../../widgets/chat_model_selector.dart';

class OptimizerConfigPanel extends StatelessWidget {
  final int? selectedModelPk;
  final int? selectedTagId;
  final String? selectedSysPrompt;
  final List<PromptTag> tags;
  final List<SystemPrompt> filteredSysPrompts;
  final Function(int?) onModelChanged;
  final Function(int?) onTagChanged;
  final Function(String?) onSysPromptChanged;
  final ScrollController? scrollController;

  const OptimizerConfigPanel({
    super.key,
    required this.selectedModelPk,
    required this.selectedTagId,
    required this.selectedSysPrompt,
    required this.tags,
    required this.filteredSysPrompts,
    required this.onModelChanged,
    required this.onTagChanged,
    required this.onSysPromptChanged,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.config.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2),
        ),
        const SizedBox(height: 16),
        
        ChatModelSelector(
          selectedModelId: selectedModelPk,
          label: l10n.refinerModel,
          onChanged: onModelChanged,
        ),
        
        const SizedBox(height: 24),
        
        _buildTagSelector(l10n, colorScheme),
        
        const SizedBox(height: 24),
        
        _buildSysPromptSelector(l10n, colorScheme),
      ],
    );

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      child: content,
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
          value: selectedTagId,
          isDense: true,
          isExpanded: true,
          onChanged: onTagChanged,
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(l10n.catAll)),
            ...tags.map((t) => DropdownMenuItem<int?>(
              value: t.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(backgroundColor: Color(t.color), radius: 6),
                  const SizedBox(width: 8),
                  Text(t.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSysPromptSelector(AppLocalizations l10n, ColorScheme colorScheme) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.systemPrompt,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedSysPrompt,
          isDense: true,
          isExpanded: true,
          onChanged: onSysPromptChanged,
          items: filteredSysPrompts.map((p) => DropdownMenuItem(
            value: p.content, 
            child: Text(p.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))
          )).toList(),
        ),
      ),
    );
  }
}
