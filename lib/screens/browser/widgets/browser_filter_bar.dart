import 'package:flutter/material.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/browser_file.dart';
import '../../../state/file_browser_state.dart';

/// Single control row under the header: category chips on the left,
/// sort control and thumbnail-size slider on the right.
class BrowserFilterBar extends StatelessWidget {
  final FileBrowserState state;

  const BrowserFilterBar({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isNarrow = Responsive.isNarrow(context);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: FileCategory.values.map((cat) {
                final isSelected = state.currentFilter == cat;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                  child: FilterChip(
                    label: Text(_getCategoryLabel(cat, l10n), style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => state.setFilter(cat),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: true,
                    side: isSelected ? BorderSide.none : BorderSide(color: colorScheme.outlineVariant),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 8),
          _buildSortControl(context, l10n, colorScheme),
          if (state.viewMode == BrowserViewMode.grid) ...[
            const SizedBox(width: 8),
            if (!isNarrow)
              _buildThumbnailSlider(colorScheme)
            else
              IconButton(
                icon: const Icon(Icons.photo_size_select_large, size: 18),
                onPressed: () => _showThumbnailSizeDialog(context, l10n),
                tooltip: l10n.thumbnailSize,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ],
      ),
    );
  }

  /// Sort field and direction combined into one popup menu.
  Widget _buildSortControl(BuildContext context, AppLocalizations l10n, ColorScheme colorScheme) {
    return PopupMenuButton<Object>(
      tooltip: l10n.sortBy,
      onSelected: (value) {
        if (value is BrowserSortField) {
          state.setSortField(value);
        } else if (value is bool) {
          state.setSortAscending(value);
        }
      },
      itemBuilder: (context) => [
        for (final field in BrowserSortField.values)
          CheckedPopupMenuItem(
            value: field,
            checked: state.sortField == field,
            child: Text(_getSortFieldLabel(field, l10n), style: const TextStyle(fontSize: 13)),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: true,
          checked: state.sortAscending,
          child: Text(l10n.sortAsc, style: const TextStyle(fontSize: 13)),
        ),
        CheckedPopupMenuItem(
          value: false,
          checked: !state.sortAscending,
          child: Text(l10n.sortDesc, style: const TextStyle(fontSize: 13)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              _getSortFieldLabel(state.sortField, l10n),
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailSlider(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_outlined, size: 14, color: colorScheme.outline),
        SizedBox(
          width: 96,
          child: SliderTheme(
            data: const SliderThemeData(
              trackHeight: 3,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: state.thumbnailSize,
              min: 80,
              max: 400,
              onChanged: (v) => state.setThumbnailSize(v),
            ),
          ),
        ),
        Icon(Icons.image, size: 18, color: colorScheme.outline),
      ],
    );
  }

  void _showThumbnailSizeDialog(BuildContext context, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.thumbnailSize),
        content: StatefulBuilder(
          builder: (context, setState) {
            double val = state.thumbnailSize;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: val,
                  min: 80,
                  max: 400,
                  onChanged: (v) {
                    state.setThumbnailSize(v);
                    setState(() => val = v);
                  },
                ),
                Text("${val.toInt()}px"),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK")),
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
