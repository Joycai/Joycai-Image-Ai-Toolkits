import 'package:flutter/material.dart';
import '../../services/database_service.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _models = [];

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    final models = await _db.getModels();
    setState(() {
      _models = List.from(models);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Manager'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              onPressed: () => _showModelDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Model'),
            ),
          ),
        ],
      ),
      body: _models.isEmpty
          ? _buildEmptyState()
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ReorderableListView(
                  onReorder: (oldIndex, newIndex) async {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _models.removeAt(oldIndex);
                      _models.insert(newIndex, item);
                    });
                    await _db.updateModelOrder(_models.map((m) => m['id'] as int).toList());
                  },
                  children: _models.map((model) => ListTile(
                    key: ValueKey(model['id']),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(model['model_name']),
                    subtitle: Text('${model['type']} | ${model['tag']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (model['is_paid'] == 1)
                          const Padding(
                            padding: EdgeInsets.only(right: 8.0),
                            child: Chip(
                              label: Text('PAID', style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showModelDialog(model: model),
                          tooltip: 'Edit Model',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDeleteModel(model),
                          tooltip: 'Delete Model',
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
          Icon(Icons.model_training_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('No models configured', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Add your first LLM model to get started', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showModelDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add New Model'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteModel(Map<String, dynamic> model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model?'),
        content: Text('Are you sure you want to delete "${model['model_name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.deleteModel(model['id']);
              Navigator.pop(context);
              _loadModels();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showModelDialog({Map<String, dynamic>? model}) {
    final idCtrl = TextEditingController(text: model?['model_id'] ?? '');
    final nameCtrl = TextEditingController(text: model?['model_name'] ?? '');
    String type = model?['type'] ?? 'google-genai';
    String tag = model?['tag'] ?? 'chat';
    bool isPaid = (model?['is_paid'] ?? 0) == 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(model == null ? 'Add LLM Model' : 'Edit LLM Model'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'Model ID (e.g. gemini-pro)')),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Display Name')),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'google-genai', child: Text('Google GenAI')),
                    DropdownMenuItem(value: 'openai-api', child: Text('OpenAI API')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v!),
                  decoration: const InputDecoration(labelText: 'Type'),
                ),
                DropdownButtonFormField<String>(
                  value: tag,
                  items: const [
                    DropdownMenuItem(value: 'chat', child: Text('Chat')),
                    DropdownMenuItem(value: 'image', child: Text('Image')),
                    DropdownMenuItem(value: 'multimodal', child: Text('Multimodal')),
                  ],
                  onChanged: (v) => setDialogState(() => tag = v!),
                  decoration: const InputDecoration(labelText: 'Tag'),
                ),
                SwitchListTile(
                  title: const Text('Paid Model'),
                  value: isPaid,
                  onChanged: (v) => setDialogState(() => isPaid = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'model_id': idCtrl.text,
                  'model_name': nameCtrl.text,
                  'type': type,
                  'tag': tag,
                  'is_paid': isPaid ? 1 : 0,
                };
                
                if (model == null) {
                  data['sort_order'] = _models.length;
                  await _db.addModel(data);
                } else {
                  await _db.updateModel(model['id'], data);
                }
                
                Navigator.pop(context);
                _loadModels();
              },
              child: Text(model == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
