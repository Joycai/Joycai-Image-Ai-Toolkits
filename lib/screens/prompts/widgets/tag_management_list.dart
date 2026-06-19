import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/tag.dart';
import '../../../services/database_service.dart';

class TagManagementList extends StatefulWidget {
  final List<PromptTag> tags;
  final VoidCallback onRefresh;
  final Function(AppLocalizations, {PromptTag? tag}) onShowEditDialog;
  final Function(AppLocalizations, PromptTag tag) onConfirmDelete;

  /// Number of prompts in each category, keyed by tag id.
  final Map<int, int> promptCounts;

  const TagManagementList({
    super.key,
    required this.tags,
    required this.onRefresh,
    required this.onShowEditDialog,
    required this.onConfirmDelete,
    this.promptCounts = const {},
  });

  @override
  State<TagManagementList> createState() => _TagManagementListState();
}

class _TagManagementListState extends State<TagManagementList> {
  final DatabaseService _db = DatabaseService();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final tags = widget.tags;

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tags.length,
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = tags.removeAt(oldIndex);
          tags.insert(newIndex, item);
        });
        await _db.updateTagOrder(tags.map((t) => t.id!).toList());
        widget.onRefresh();
      },
      itemBuilder: (context, index) {
        final tag = tags[index];
        final color = Color(tag.color);
        final count = widget.promptCounts[tag.id] ?? 0;
        return Card(
          key: ValueKey('tag_${tag.id}'),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colorScheme.outlineVariant.withAlpha(120)),
          ),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_indicator, color: colorScheme.outline, size: 20),
                ),
                const SizedBox(width: 8),
                CircleAvatar(backgroundColor: color, radius: 12),
              ],
            ),
            title: Text(tag.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withAlpha(24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color.withAlpha(230),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => widget.onShowEditDialog(l10n, tag: tag),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  onPressed: () => widget.onConfirmDelete(l10n, tag),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
