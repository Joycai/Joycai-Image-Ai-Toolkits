import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/prompt.dart';
import '../../../services/database_service.dart';
import '../../../widgets/prompt_card.dart';

class SystemTemplateList extends StatefulWidget {
  final List<SystemPrompt> prompts;
  final String searchQuery;
  final VoidCallback onRefresh;
  final Function(AppLocalizations, {SystemPrompt? prompt}) onShowEditDialog;
  final Function(AppLocalizations, dynamic prompt, {required bool isSystem}) onConfirmDelete;

  const SystemTemplateList({
    super.key,
    required this.prompts,
    required this.searchQuery,
    required this.onRefresh,
    required this.onShowEditDialog,
    required this.onConfirmDelete,
  });

  @override
  State<SystemTemplateList> createState() => _SystemTemplateListState();
}

class _SystemTemplateListState extends State<SystemTemplateList> {
  final DatabaseService _db = DatabaseService();
  final Set<int> _expandedSysPromptIds = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final prompts = widget.prompts;

    if (prompts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_fix_high, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              l10n.noPromptsSaved, 
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            ),
            const SizedBox(height: 8),
            const Text(
              "Add system templates for the Refiner or Batch Rename here.", 
              style: TextStyle(color: Colors.grey)
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
        if (widget.searchQuery.isNotEmpty) return;
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = prompts.removeAt(oldIndex);
          prompts.insert(newIndex, item);
        });
        await _db.updateSystemPromptOrder(prompts.map((p) => p.id!).toList());
        widget.onRefresh();
      },
      itemBuilder: (context, index) {
        final systemPrompt = prompts[index];
        final id = systemPrompt.id!;
        final isExpanded = _expandedSysPromptIds.contains(id);

        // Map to Prompt for PromptCard
        final promptForCard = Prompt(
          id: systemPrompt.id,
          title: systemPrompt.title,
          content: systemPrompt.content,
          isMarkdown: systemPrompt.isMarkdown,
          tags: systemPrompt.tags,
        );

        return Padding(
          key: ValueKey('sys_$id'),
          padding: const EdgeInsets.only(bottom: 12),
          child: PromptCard(
            prompt: promptForCard,
            isExpanded: isExpanded,
            onToggle: () => setState(() {
              if (isExpanded) {
                _expandedSysPromptIds.remove(id);
              } else {
                _expandedSysPromptIds.add(id);
              }
            }),
            leading: widget.searchQuery.isEmpty 
                ? ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20))
                : Icon(systemPrompt.type == 'refiner' ? Icons.auto_fix_high : Icons.drive_file_rename_outline, color: Colors.purple, size: 20),
            showCategory: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: systemPrompt.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.copiedToClipboard(systemPrompt.title))),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => widget.onShowEditDialog(l10n, prompt: systemPrompt),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => widget.onConfirmDelete(l10n, systemPrompt, isSystem: true),
              ),
            ],
          ),
        );
      },
    );
  }
}
