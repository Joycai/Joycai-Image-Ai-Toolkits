import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/tag.dart';
import '../../../services/database_service.dart';

class TagManagementList extends StatefulWidget {
  final List<PromptTag> tags;
  final VoidCallback onRefresh;
  final Function(AppLocalizations, {PromptTag? tag}) onShowEditDialog;
  final Function(AppLocalizations, PromptTag tag) onConfirmDelete;

  const TagManagementList({
    super.key,
    required this.tags,
    required this.onRefresh,
    required this.onShowEditDialog,
    required this.onConfirmDelete,
  });

  @override
  State<TagManagementList> createState() => _TagManagementListState();
}

class _TagManagementListState extends State<TagManagementList> {
  final DatabaseService _db = DatabaseService();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tags = widget.tags;

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tags.length,
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
        return Card(
          key: ValueKey('tag_${tag.id}'),
          child: ListTile(
            leading: ReorderableDragStartListener(
              index: index,
              child: CircleAvatar(
                backgroundColor: Color(tag.color),
                radius: 12,
              ),
            ),
            title: Text(tag.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => widget.onShowEditDialog(l10n, tag: tag),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
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
