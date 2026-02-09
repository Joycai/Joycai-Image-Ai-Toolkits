import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/llm_model.dart';
import '../../state/app_state.dart';

class ModelEditDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final AppState appState;
  final LLMModel? model;
  final int? preChannelId;

  const ModelEditDialog({
    super.key,
    required this.l10n,
    required this.appState,
    this.model,
    this.preChannelId,
  });

  @override
  State<ModelEditDialog> createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<ModelEditDialog> {
  late TextEditingController idCtrl;
  late TextEditingController nameCtrl;
  
  int? channelId;
  late String tag;
  int? feeGroupId;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    idCtrl = TextEditingController(text: model?.modelId ?? '');
    nameCtrl = TextEditingController(text: model?.modelName ?? '');
    
    channelId = model?.channelId ?? widget.preChannelId ?? (widget.appState.allChannels.isNotEmpty ? widget.appState.allChannels.first.id : null);
    tag = model?.tag ?? 'chat';
    feeGroupId = model?.feeGroupId;
  }

  @override
  void dispose() {
    idCtrl.dispose();
    nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final appState = widget.appState;

    return AlertDialog(
      title: Text(widget.model == null ? l10n.addLlmModel : l10n.editLlmModel),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: channelId,
              items: appState.allChannels.map((c) => DropdownMenuItem(
                value: c.id!,
                child: Text(c.displayName),
              )).toList(),
              onChanged: (v) => setState(() => channelId = v),
              decoration: InputDecoration(labelText: l10n.channel),
            ),
            TextField(controller: idCtrl, decoration: InputDecoration(labelText: l10n.modelIdLabel)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.displayName)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: tag,
              items: const [
                DropdownMenuItem(value: 'chat', child: Text('Chat')),
                DropdownMenuItem(value: 'image', child: Text('Image')),
                DropdownMenuItem(value: 'multimodal', child: Text('Multimodal')),
              ],
              onChanged: (v) => setState(() => tag = v!),
              decoration: InputDecoration(labelText: l10n.tag),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: feeGroupId,
              items: [
                 DropdownMenuItem(value: null, child: Text(l10n.noFeeGroup, style: const TextStyle(color: Colors.grey))),
                ...appState.allFeeGroups.map((g) => DropdownMenuItem(
                  value: g.id!, 
                  child: Text(g.name),
                )),
              ],
              onChanged: (v) => setState(() => feeGroupId = v),
              decoration: InputDecoration(labelText: l10n.feeGroup),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ElevatedButton(
          onPressed: channelId == null ? null : () async {
            final channel = appState.allChannels.firstWhere((c) => c.id == channelId);
            final data = {
              'model_id': idCtrl.text,
              'model_name': nameCtrl.text,
              'type': channel.type.contains('google') ? 'google-genai' : 'openai-api',
              'tag': tag,
              'is_paid': 1, // Simplified, derived from channel if needed
              'fee_group_id': feeGroupId,
              'channel_id': channelId,
            };
            
            if (widget.model == null) {
              await widget.appState.addModel(data);
            } else {
              await widget.appState.updateModel(widget.model!.id!, data);
            }
            
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(widget.model == null ? l10n.add : l10n.save),
        ),
      ],
    );
  }
}