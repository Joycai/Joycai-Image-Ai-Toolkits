import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.modelManager),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              onPressed: () => _showModelDialog(l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.addModel),
            ),
          ),
        ],
      ),
      body: _models.isEmpty
          ? _buildEmptyState(l10n)
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
                    subtitle: Text(model['billing_mode'] == 'request' 
                      ? '${model['type']} | ${model['tag']} | \$${model['request_fee']}/Req'
                      : '${model['type']} | ${model['tag']} | In: \$${model['input_fee']}/M | Out: \$${model['output_fee']}/M'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (model['is_paid'] == 1)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Chip(
                              label: Text(l10n.paidModel.toUpperCase(), style: const TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showModelDialog(l10n, model: model),
                          tooltip: l10n.editModel,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDeleteModel(l10n, model),
                          tooltip: l10n.deleteModel,
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
          Icon(Icons.model_training_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(l10n.noModelsConfigured, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.addFirstModel, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showModelDialog(l10n),
            icon: const Icon(Icons.add),
            label: Text(l10n.addNewModel),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteModel(AppLocalizations l10n, Map<String, dynamic> model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteModelConfirmTitle),
        content: Text(l10n.deleteModelConfirmMessage(model['model_name'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.deleteModel(model['id']);
              if (context.mounted) {
                Navigator.pop(context);
                _loadModels();
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showModelDialog(AppLocalizations l10n, {Map<String, dynamic>? model}) {
    final idCtrl = TextEditingController(text: model?['model_id'] ?? '');
    final nameCtrl = TextEditingController(text: model?['model_name'] ?? '');
    final inputFeeCtrl = TextEditingController(text: (model?['input_fee'] ?? 0.0).toString());
    final outputFeeCtrl = TextEditingController(text: (model?['output_fee'] ?? 0.0).toString());
    final requestFeeCtrl = TextEditingController(text: (model?['request_fee'] ?? 0.0).toString());
    
    String type = model?['type'] ?? 'google-genai';
    String tag = model?['tag'] ?? 'chat';
    String billingMode = model?['billing_mode'] ?? 'token';
    bool isPaid = (model?['is_paid'] ?? 0) == 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(model == null ? l10n.addLlmModel : l10n.editLlmModel),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: idCtrl, decoration: InputDecoration(labelText: l10n.modelIdLabel)),
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.displayName)),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(value: 'google-genai', child: Text('Google GenAI')),
                    DropdownMenuItem(value: 'openai-api', child: Text('OpenAI API')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v!),
                  decoration: InputDecoration(labelText: l10n.type),
                ),
                DropdownButtonFormField<String>(
                  initialValue: tag,
                  items: const [
                    DropdownMenuItem(value: 'chat', child: Text('Chat')),
                    DropdownMenuItem(value: 'image', child: Text('Image')),
                    DropdownMenuItem(value: 'multimodal', child: Text('Multimodal')),
                  ],
                  onChanged: (v) => setDialogState(() => tag = v!),
                  decoration: InputDecoration(labelText: l10n.tag),
                ),
                DropdownButtonFormField<String>(
                  initialValue: billingMode,
                  items: [
                    DropdownMenuItem(value: 'token', child: Text(l10n.perToken)),
                    DropdownMenuItem(value: 'request', child: Text(l10n.perRequest)),
                  ],
                  onChanged: (v) => setDialogState(() => billingMode = v!),
                  decoration: InputDecoration(labelText: l10n.billingMode),
                ),
                const SizedBox(height: 16),
                if (billingMode == 'token')
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputFeeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: l10n.inputFeeLabel, border: const OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: outputFeeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: l10n.outputFeeLabel, border: const OutlineInputBorder()),
                        ),
                      ),
                    ],
                  )
                else
                  TextField(
                    controller: requestFeeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.requestFeeLabel, border: const OutlineInputBorder()),
                  ),
                SwitchListTile(
                  title: Text(l10n.paidModel),
                  value: isPaid,
                  onChanged: (v) => setDialogState(() => isPaid = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'model_id': idCtrl.text,
                  'model_name': nameCtrl.text,
                  'type': type,
                  'tag': tag,
                  'is_paid': isPaid ? 1 : 0,
                  'input_fee': double.tryParse(inputFeeCtrl.text) ?? 0.0,
                  'output_fee': double.tryParse(outputFeeCtrl.text) ?? 0.0,
                  'billing_mode': billingMode,
                  'request_fee': double.tryParse(requestFeeCtrl.text) ?? 0.0,
                };
                
                if (model == null) {
                  data['sort_order'] = _models.length;
                  await _db.addModel(data);
                } else {
                  await _db.updateModel(model['id'], data);
                }
                
                if (context.mounted) {
                  Navigator.pop(context);
                  _loadModels();
                }
              },
              child: Text(model == null ? l10n.add : l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
