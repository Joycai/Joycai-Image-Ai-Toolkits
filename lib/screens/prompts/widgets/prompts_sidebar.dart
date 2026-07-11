import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/tag.dart';

class PromptsSidebar extends StatelessWidget {
  final List<PromptTag> tags;
  final Set<int> selectedFilterTagIds;
  final ValueChanged<int> onTagToggle;
  final VoidCallback onClear;

  /// Number of prompts in the active list per tag id.
  final Map<int, int> tagCounts;

  /// Total number of prompts in the active list (the "All" entry count).
  final int totalCount;

  /// When multiple categories are selected: false = match any, true = match all.
  final bool matchAll;
  final ValueChanged<bool>? onMatchModeChanged;

  const PromptsSidebar({
    super.key,
    required this.tags,
    required this.selectedFilterTagIds,
    required this.onTagToggle,
    required this.onClear,
    this.tagCounts = const {},
    this.totalCount = 0,
    this.matchAll = false,
    this.onMatchModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final allSelected = selectedFilterTagIds.isEmpty;

    // Transparent: the hosting PanelCard's surface is the background.
    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.categoriesTab.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _SidebarTile(
                  leading: Icon(
                    Icons.layers_outlined,
                    color: allSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  label: l10n.filterAll,
                  count: totalCount,
                  selected: allSelected,
                  onTap: onClear,
                ),
                Divider(height: 12, color: colorScheme.outlineVariant.withAlpha(80)),
                ...tags.map((tag) {
                  final isSelected = selectedFilterTagIds.contains(tag.id);
                  return _SidebarTile(
                    leading: Icon(
                      isSelected ? Icons.label : Icons.label_outline,
                      color: Color(tag.color),
                      size: 18,
                    ),
                    label: tag.name,
                    count: tagCounts[tag.id] ?? 0,
                    selected: isSelected,
                    onTap: () => onTagToggle(tag.id!),
                  );
                }),
              ],
            ),
          ),
          // Match mode toggle — only relevant when filtering by 2+ categories.
          if (selectedFilterTagIds.length >= 2 && onMatchModeChanged != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Row(
                children: [
                  Text(
                    '${l10n.matchModeLabel}:',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<bool>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                      ),
                      segments: [
                        ButtonSegment(value: false, label: Text(l10n.matchAny)),
                        ButtonSegment(value: true, label: Text(l10n.matchAllTags)),
                      ],
                      selected: {matchAll},
                      onSelectionChanged: (s) => onMatchModeChanged!(s.first),
                      showSelectedIcon: false,
                    ),
                  ),
                ],
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

class _SidebarTile extends StatelessWidget {
  final Widget leading;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.leading,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary.withAlpha(28) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          margin: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? colorScheme.primary : colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
