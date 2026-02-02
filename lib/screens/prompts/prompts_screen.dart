import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';

class PromptsScreen extends StatefulWidget {
  const PromptsScreen({super.key});

  @override
  State<PromptsScreen> createState() => _PromptsScreenState();
}

class _PromptsScreenState extends State<PromptsScreen> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _prompts = [];

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    final prompts = await _db.getPrompts();
    setState(() {
      _prompts = List.from(prompts);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.promptLibrary),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              onPressed: () => _showPromptDialog(l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.newPrompt),
            ),
          ),
        ],
      ),
      body: _prompts.isEmpty
          ? _buildEmptyState(l10n)
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ReorderableListView(
                  onReorder: (oldIndex, newIndex) async {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _prompts.removeAt(oldIndex);
                      _prompts.insert(newIndex, item);
                    });
                    await _db.updatePromptOrder(_prompts.map((p) => p['id'] as int).toList());
                  },
                  children: _prompts.map((prompt) => ListTile(
                    key: ValueKey(prompt['id']),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(prompt['title']),
                    subtitle: Text(
                      prompt['content'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(prompt['tag'], style: const TextStyle(fontSize: 10)),
                          color: prompt['tag'] == 'Refiner' ? WidgetStateProperty.all(Theme.of(context).colorScheme.tertiaryContainer) : null,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showPromptDialog(l10n, prompt: prompt),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(l10n, prompt),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notes, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(l10n.noPromptsSaved, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.saveFavoritePrompts, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showPromptDialog(l10n),
            icon: const Icon(Icons.add),
            label: Text(l10n.createFirstPrompt),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(AppLocalizations l10n, Map<String, dynamic> prompt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePromptConfirmTitle),
        content: Text(l10n.deletePromptConfirmMessage(prompt['title'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.deletePrompt(prompt['id']);
              if (context.mounted) {
                Navigator.pop(context);
                _loadPrompts();
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPromptDialog(AppLocalizations l10n, {Map<String, dynamic>? prompt}) {
    final titleCtrl = TextEditingController(text: prompt?['title'] ?? '');
    final contentCtrl = TextEditingController(text: prompt?['content'] ?? '');
    final tagCtrl = TextEditingController(text: prompt?['tag'] ?? 'General');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(prompt == null ? l10n.newPrompt : l10n.editPrompt),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: InputDecoration(labelText: l10n.title)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: TextField(controller: tagCtrl, decoration: InputDecoration(labelText: l10n.tagCategory))),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => tagCtrl.text = 'Refiner',
                      child: Text(l10n.setAsRefiner),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentCtrl,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: l10n.promptContent,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () async {
              final Map<String, dynamic> data = {
                'title': titleCtrl.text,
                'content': contentCtrl.text,
                'tag': tagCtrl.text.isEmpty ? 'General' : tagCtrl.text,
              };
              if (prompt == null) {
                data['sort_order'] = _prompts.length;
                await _db.addPrompt(data);
              } else {
                await _db.updatePrompt(prompt['id'] as int, data);
              }
              if (context.mounted) {
                Navigator.pop(context);
                _loadPrompts();
              }
            },
            child: Text(prompt == null ? l10n.save : l10n.update),
          ),
        ],
      ),
    );
  }
}
