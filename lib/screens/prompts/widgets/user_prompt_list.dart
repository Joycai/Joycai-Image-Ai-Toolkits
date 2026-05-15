import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../services/database_service.dart';
import '../../../widgets/prompt_card.dart';

class UserPromptList extends StatefulWidget {
  final List<Prompt> prompts;
  final String searchQuery;
  final Set<int> selectedFilterTagIds;
  final VoidCallback onRefresh;
  final Function(AppLocalizations, {Prompt? prompt}) onShowEditDialog;
  final Function(AppLocalizations, dynamic prompt, {required bool isSystem}) onConfirmDelete;
  
  final Set<int> selectedIds;
  final bool isSelectionMode;
  final Function(int) onToggleSelection;
  final Function(int) onEnterSelectionMode;

  const UserPromptList({
    super.key,
    required this.prompts,
    required this.searchQuery,
    required this.selectedFilterTagIds,
    required this.onRefresh,
    required this.onShowEditDialog,
    required this.onConfirmDelete,
    required this.selectedIds,
    required this.isSelectionMode,
    required this.onToggleSelection,
    required this.onEnterSelectionMode,
  });

  @override
  State<UserPromptList> createState() => _UserPromptListState();
}

class _UserPromptListState extends State<UserPromptList> {
  final DatabaseService _db = DatabaseService();
  final Set<int> _expandedPromptIds = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final prompts = widget.prompts;

    if (prompts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notes, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              l10n.noPromptsSaved,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold) 
            ),
            const SizedBox(height: 8),
            Text(
              l10n.saveFavoritePrompts,
              style: const TextStyle(color: Colors.grey)
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => widget.onShowEditDialog(l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.newPrompt),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: prompts.length,
      onReorder: (oldIndex, newIndex) async {
        if (widget.searchQuery.isNotEmpty || widget.selectedFilterTagIds.isNotEmpty) return;

        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = prompts.removeAt(oldIndex);
          prompts.insert(newIndex, item);
        });
        await _db.updatePromptOrder(prompts.map((p) => p.id!).toList());        
        widget.onRefresh();
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: child,
      ),
      itemBuilder: (context, index) {
        final prompt = prompts[index];
        final id = prompt.id!;
        final isExpanded = _expandedPromptIds.contains(id);
        final isSelected = widget.selectedIds.contains(id);

        return Padding(
          key: ValueKey('user_$id'),
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onLongPress: () => widget.onEnterSelectionMode(id),
            child: PromptCard(
              prompt: prompt,
              isExpanded: isExpanded,
              onToggle: widget.isSelectionMode 
                ? () => widget.onToggleSelection(id)
                : () => setState(() {
                  if (isExpanded) {
                    _expandedPromptIds.remove(id);
                  } else {
                    _expandedPromptIds.add(id);
                  }
                }),
              leading: widget.isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => widget.onToggleSelection(id),
                  )
                : null,
              onMoveToTop: (index == 0 || widget.isSelectionMode) ? null : () async {
                setState(() {
                  final item = prompts.removeAt(prompts.indexWhere((p) => p.id == id));
                  prompts.insert(0, item);
                });
                await _db.updatePromptOrder(prompts.map((p) => p.id!).toList());
                widget.onRefresh();
              },
              onMoveToBottom: (index == prompts.length - 1 || widget.isSelectionMode) ? null : () async {     
                setState(() {
                  final item = prompts.removeAt(prompts.indexWhere((p) => p.id == id));
                  prompts.add(item);
                });
                await _db.updatePromptOrder(prompts.map((p) => p.id!).toList());  
                widget.onRefresh();
              },
              actions: widget.isSelectionMode ? [] : [
                IconButton(
                  icon: const Icon(Icons.copy_all, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: prompt.content));       
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.copiedToClipboard(prompt.title))),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => widget.onShowEditDialog(l10n, prompt: prompt), 
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () => widget.onConfirmDelete(l10n, prompt, isSystem: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
