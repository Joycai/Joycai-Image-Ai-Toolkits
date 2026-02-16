import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/tag.dart';

class PromptsSidebar extends StatelessWidget {
  final List<PromptTag> tags;
  final Set<int> selectedFilterTagIds;
  final ValueChanged<int> onTagToggle;
  final VoidCallback onClear;

  const PromptsSidebar({
    super.key,
    required this.tags,
    required this.selectedFilterTagIds,
    required this.onTagToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: 250,
      color: colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              l10n.categoriesTab,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: tags.length,
              itemBuilder: (context, index) {
                final tag = tags[index];
                final isSelected = selectedFilterTagIds.contains(tag.id);
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isSelected ? Icons.label : Icons.label_outline,
                    color: Color(tag.color),
                    size: 18,
                  ),
                  title: Text(tag.name),
                  selected: isSelected,
                  onTap: () => onTagToggle(tag.id!),
                );
              },
            ),
          ),
          if (selectedFilterTagIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear_all, size: 16),
                label: Text(l10n.clear, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}
