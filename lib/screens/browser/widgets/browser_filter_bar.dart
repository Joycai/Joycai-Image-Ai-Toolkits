import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../state/browser_state.dart';

class BrowserFilterBar extends StatelessWidget {
  final BrowserState state;

  const BrowserFilterBar({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(50),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: FileCategory.values.map((cat) {
                final isSelected = state.currentFilter == cat;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: FilterChip(
                    label: Text(_getCategoryLabel(cat, l10n), style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => state.setFilter(cat),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const VerticalDivider(width: 16, indent: 12, endIndent: 12),
          
          // Sort Options
          if (!isMobile) ...[
            Text(l10n.sortBy, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
          ],
          
          PopupMenuButton<BrowserSortField>(
            initialValue: state.sortField,
            tooltip: l10n.sortBy,
            onSelected: (field) => state.setSortField(field),
            itemBuilder: (context) => [
              PopupMenuItem(value: BrowserSortField.name, child: Text(l10n.sortName)),
              PopupMenuItem(value: BrowserSortField.date, child: Text(l10n.sortDate)),
              PopupMenuItem(value: BrowserSortField.type, child: Text(l10n.sortType)),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_getSortFieldLabel(state.sortField, l10n), style: const TextStyle(fontSize: 11)),
                  const Icon(Icons.arrow_drop_down, size: 14),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(state.sortAscending ? Icons.south : Icons.north, size: 16),
            onPressed: () => state.setSortAscending(!state.sortAscending),
            tooltip: state.sortAscending ? l10n.sortAsc : l10n.sortDesc,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  String _getSortFieldLabel(BrowserSortField field, AppLocalizations l10n) {
    switch (field) {
      case BrowserSortField.name: return l10n.sortName;
      case BrowserSortField.date: return l10n.sortDate;
      case BrowserSortField.type: return l10n.sortType;
    }
  }

  String _getCategoryLabel(FileCategory cat, AppLocalizations l10n) {
    switch (cat) {
      case FileCategory.all: return l10n.catAll;
      case FileCategory.image: return l10n.catImages;
      case FileCategory.video: return l10n.catVideos;
      case FileCategory.audio: return l10n.catAudio;
      case FileCategory.text: return l10n.catText;
      case FileCategory.other: return l10n.catOthers;
    }
  }
}