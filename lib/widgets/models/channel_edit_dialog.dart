import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../api_key_field.dart';

class ChannelEditDialog extends StatefulWidget {
  final AppLocalizations l10n;
  final AppState appState;
  final Map<String, dynamic>? channel;

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
    nameCtrl = TextEditingController(text: channel?['display_name'] ?? '');
    epCtrl = TextEditingController(text: channel?['endpoint'] ?? '');
    keyCtrl = TextEditingController(text: channel?['api_key'] ?? '');
    tagCtrl = TextEditingController(text: channel?['tag'] ?? '');
    
    type = channel?['type'] ?? 'google-genai-rest';
    discovery = (channel?['enable_discovery'] ?? 1) == 1;
    tagColor = channel?['tag_color'] ?? AppConstants.tagColors.first.toARGB32();
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
    
    String endpointHint = "";
    if (type == 'openai-api-rest') {
      endpointHint = "Hint: OpenAI compatible endpoints usually end with '/v1'";
    } else if (type.contains('google')) {
      endpointHint = "Hint: Google GenAI endpoints usually end with '/v1beta' (internal handling)";
    }

    return AlertDialog(
      title: Text(widget.channel == null ? l10n.addChannel : l10n.editChannel),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.displayName)),
            DropdownButtonFormField<String>(
              initialValue: type,
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
                      epCtrl.text = 'https://generativelanguage.googleapis.com';
                    }
                  }
                });
              },
              decoration: InputDecoration(labelText: l10n.channelType),
            ),
            TextField(
              controller: epCtrl, 
              decoration: InputDecoration(
                labelText: l10n.endpointUrl,
                helperText: endpointHint,
                helperStyle: const TextStyle(color: Colors.blueGrey),
              ),
            ),
            ApiKeyField(controller: keyCtrl, label: l10n.apiKey, onChanged: (v) {}),
            SwitchListTile(
              title: Text(l10n.enableDiscovery),
              value: discovery,
              onChanged: (v) => setState(() => discovery = v),
            ),
            TextField(controller: tagCtrl, decoration: InputDecoration(labelText: l10n.tag)),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerLeft, child: Text(l10n.tagColor, style: const TextStyle(fontSize: 12))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.tagColors.map((color) => InkWell(
                onTap: () => setState(() => tagColor = color.toARGB32()),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: tagColor == color.toARGB32() ? Colors.black : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ElevatedButton(
          onPressed: () async {
            final data = {
              'display_name': nameCtrl.text,
              'endpoint': epCtrl.text,
              'api_key': keyCtrl.text,
              'type': type,
              'enable_discovery': discovery ? 1 : 0,
              'tag': tagCtrl.text,
              'tag_color': tagColor,
            };
            if (widget.channel == null) {
              await widget.appState.addChannel(data);
            } else {
              await widget.appState.updateChannel(widget.channel!['id'], data);
            }
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
