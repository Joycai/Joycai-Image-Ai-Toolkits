import 'package:flutter/material.dart';

import '../../core/responsive.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(l10n.basicInfo),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: channelId,
            isExpanded: true,
            items: appState.allChannels.map((c) => DropdownMenuItem(
              value: c.id!,
              child: Text(c.displayName),
            )).toList(),
            onChanged: (v) => setState(() => channelId = v),
            decoration: InputDecoration(
              labelText: l10n.channel,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.hub_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl, 
            decoration: InputDecoration(
              labelText: l10n.displayName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.badge_outlined),
              hintText: "e.g. GPT-4o, Gemini Pro",
            ),
          ),
          
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.configuration),
          const SizedBox(height: 12),
          TextField(
            controller: idCtrl, 
            decoration: InputDecoration(
              labelText: l10n.modelIdLabel,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.fingerprint),
              hintText: "e.g. gpt-4, gemini-1.5-pro",
              helperText: "The exact ID required by the API provider",
              helperStyle: TextStyle(color: colorScheme.outline, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: tag,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'chat', child: Text('Chat')),
              DropdownMenuItem(value: 'image', child: Text('Image')),
              DropdownMenuItem(value: 'multimodal', child: Text('Multimodal')),
            ],
            onChanged: (v) => setState(() => tag = v!),
            decoration: InputDecoration(
              labelText: l10n.tag,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.tag),
            ),
          ),
          
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.billing),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: feeGroupId,
            isExpanded: true,
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.noFeeGroup, style: TextStyle(color: colorScheme.outline))),
              ...appState.allFeeGroups.map((g) => DropdownMenuItem(
                value: g.id!, 
                child: Text(g.name),
              )),
            ],
            onChanged: (v) => setState(() => feeGroupId = v),
            decoration: InputDecoration(
              labelText: l10n.feeGroup,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.model == null ? Icons.add_box_outlined : Icons.edit_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          Text(widget.model == null ? l10n.addLlmModel : l10n.editLlmModel),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 550,
          minWidth: isMobile ? 0 : 450,
        ),
        child: content,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: Text(l10n.cancel)
        ),
        FilledButton.icon(
          onPressed: (channelId == null || idCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) ? null : () async {
            final channel = appState.allChannels.firstWhere((c) => c.id == channelId);
            final data = {
              'model_id': idCtrl.text.trim(),
              'model_name': nameCtrl.text.trim(),
              'type': channel.type.contains('google') ? 'google-genai' : 'openai-api',
              'tag': tag,
              'is_paid': 1,
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
          icon: const Icon(Icons.save, size: 18),
          label: Text(widget.model == null ? l10n.add : l10n.save),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
      ],
    );
  }
}
