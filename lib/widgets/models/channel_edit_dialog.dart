import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../state/app_state.dart';
import '../api_key_field.dart';

class ChannelEditDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final AppState appState;
  final LLMChannel? channel;

  const ChannelEditDialog({
    super.key,
    required this.l10n,
    required this.appState,
    this.channel,
  });

  @override
  State<ChannelEditDialog> createState() => _ChannelEditDialogState();
}

class _ChannelEditDialogState extends State<ChannelEditDialog> {
  late TextEditingController nameCtrl;
  late TextEditingController epCtrl;
  late TextEditingController keyCtrl;
  late TextEditingController tagCtrl;
  
  late String type;
  late bool discovery;
  late int tagColor;

  @override
  void initState() {
    super.initState();
    final channel = widget.channel;
    nameCtrl = TextEditingController(text: channel?.displayName ?? '');
    epCtrl = TextEditingController(text: channel?.endpoint ?? '');
    keyCtrl = TextEditingController(text: channel?.apiKey ?? '');
    tagCtrl = TextEditingController(text: channel?.tag ?? '');
    
    type = channel?.type ?? 'google-genai-rest';
    discovery = channel?.enableDiscovery ?? true;
    tagColor = channel?.tagColor ?? AppConstants.tagColors.first.toARGB32();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    epCtrl.dispose();
    keyCtrl.dispose();
    tagCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);
    
    String endpointHint = "";
    if (type == 'openai-api-rest') {
      endpointHint = l10n.openaiEndpointHint;
    } else if (type.contains('google')) {
      endpointHint = l10n.googleEndpointHint;
    }

    final content = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Basic Info Section
          _buildSectionHeader(l10n.basicInfo),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl, 
            decoration: InputDecoration(
              labelText: l10n.displayName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: type,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'google-genai-rest', child: Text('Google GenAI REST')),
              DropdownMenuItem(value: 'openai-api-rest', child: Text('OpenAI API REST')),
              DropdownMenuItem(value: 'official-google-genai-api', child: Text('Official Google GenAI API')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                type = v;
                if (widget.channel == null) {
                  if (type == 'openai-api-rest') {
                    epCtrl.text = 'https://api.openai.com/v1';
                  } else {
                    epCtrl.text = 'https://generativelanguage.googleapis.com/v1beta';
                  }
                }
              });
            },
            decoration: InputDecoration(
              labelText: l10n.channelType,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.category_outlined),
            ),
          ),

          const SizedBox(height: 24),
          // Configuration Section
          _buildSectionHeader(l10n.configuration),
          const SizedBox(height: 12),
          TextField(
            controller: epCtrl,
            decoration: InputDecoration(
              labelText: l10n.endpointUrl,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
              helperText: endpointHint.isNotEmpty ? endpointHint : null,
              helperMaxLines: 3,
              helperStyle: TextStyle(color: colorScheme.outline, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
          ApiKeyField(
            controller: keyCtrl, 
            label: l10n.apiKey, 
            onChanged: (v) {}
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: Text(l10n.enableDiscovery, style: const TextStyle(fontSize: 14)),
            subtitle: Text("Automatically discover models from this endpoint", style: TextStyle(fontSize: 12, color: colorScheme.outline)),
            value: discovery,
            onChanged: (v) => setState(() => discovery = v),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 24),
          // Visual/Tags Section
          _buildSectionHeader(l10n.tagAndAppearance),
          const SizedBox(height: 12),
          TextField(
            controller: tagCtrl, 
            decoration: InputDecoration(
              labelText: l10n.tag,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.tag),
              hintText: "e.g. OpenAI, Local, etc.",
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.tagColor, style: TextStyle(fontSize: 12, color: colorScheme.outline, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppConstants.tagColors.map((color) {
              final isSelected = tagColor == color.toARGB32();
              return InkWell(
                onTap: () => setState(() => tagColor = color.toARGB32()),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ] : null,
                    border: Border.all(
                      color: isSelected ? colorScheme.onSurface : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: isSelected ? Icon(Icons.check, size: 20, color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black) : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );

    return AlertDialog(
      title: Row(
        children: [
          Icon(widget.channel == null ? Icons.add_link : Icons.edit_note, color: colorScheme.primary),
          const SizedBox(width: 12),
          Text(widget.channel == null ? l10n.addChannel : l10n.editChannel),
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
          onPressed: () async {
            final data = {
              'display_name': nameCtrl.text.trim(),
              'endpoint': epCtrl.text.trim(),
              'api_key': keyCtrl.text.trim(),
              'type': type,
              'enable_discovery': discovery ? 1 : 0,
              'tag': tagCtrl.text.trim(),
              'tag_color': tagColor,
            };

            if (widget.channel == null) {
              await widget.appState.addChannel(data);
            } else {
              await widget.appState.updateChannel(widget.channel!.id!, data);
            }

            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.save, size: 18),
          label: Text(l10n.save),
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
