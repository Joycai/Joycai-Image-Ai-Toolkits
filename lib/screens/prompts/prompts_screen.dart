import 'package:flutter/material.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt Library'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              onPressed: () => _showPromptDialog(),
              icon: const Icon(Icons.add),
              label: const Text('New Prompt'),
            ),
          ),
        ],
      ),
      body: _prompts.isEmpty
          ? _buildEmptyState()
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
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showPromptDialog(prompt: prompt),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(prompt),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notes, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('No prompts saved', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Save your favorite prompts for quick access', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showPromptDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Create First Prompt'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> prompt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Prompt?'),
        content: Text('Are you sure you want to delete "${prompt['title']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.deletePrompt(prompt['id']);
              Navigator.pop(context);
              _loadPrompts();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPromptDialog({Map<String, dynamic>? prompt}) {
    final titleCtrl = TextEditingController(text: prompt?['title'] ?? '');
    final contentCtrl = TextEditingController(text: prompt?['content'] ?? '');
    final tagCtrl = TextEditingController(text: prompt?['tag'] ?? 'General');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(prompt == null ? 'New Prompt' : 'Edit Prompt'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 16),
                TextField(controller: tagCtrl, decoration: const InputDecoration(labelText: 'Tag (Category)')),
                const SizedBox(height: 16),
                TextField(
                  controller: contentCtrl,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Prompt Content',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
              Navigator.pop(context);
              _loadPrompts();
            },
            child: Text(prompt == null ? 'Save' : 'Update'),
          ),
        ],
      ),
    );
  }
}
