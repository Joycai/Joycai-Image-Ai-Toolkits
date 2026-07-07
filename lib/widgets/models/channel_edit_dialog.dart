import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../state/app_state.dart';
import '../api_key_field.dart';
import 'channel_form_sections.dart';

/// Edit-channel dialog. Desktop: a fixed-width two-column layout —
/// connection (protocol, endpoint, key, discovery) on the left, appearance
/// (name, tag, color) on the right — so everything fits without scrolling.
/// Mobile: the same sections stacked in a fullscreen page.
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

  Future<void> _save() async {
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

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(l10n.editChannel),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            TextButton(
              onPressed: _save,
              child: Text(l10n.save,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChannelSectionLabel(l10n.stepConnection),
              _buildConnectionFields(l10n),
              const Divider(height: 32),
              ChannelSectionLabel(l10n.sectionAppearance),
              ChannelAppearanceSection(
                l10n: l10n,
                nameCtrl: nameCtrl,
                tagCtrl: tagCtrl,
                tagColor: tagColor,
                onColorChanged: (c) => setState(() => tagColor = c),
              ),
            ],
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      title: Row(
        children: [
          Icon(Icons.edit_note, color: colorScheme.primary),
          const SizedBox(width: 12),
          Text(l10n.editChannel),
          const Spacer(),
          if (widget.channel != null)
            Flexible(
              child: Text(
                widget.channel!.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colorScheme.outline),
              ),
            ),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChannelSectionLabel(l10n.stepConnection),
                      _buildConnectionFields(l10n),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: VerticalDivider(width: 1),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChannelSectionLabel(l10n.sectionAppearance),
                      ChannelAppearanceSection(
                        l10n: l10n,
                        nameCtrl: nameCtrl,
                        tagCtrl: tagCtrl,
                        tagColor: tagColor,
                        onColorChanged: (c) => setState(() => tagColor = c),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save, size: 18),
          label: Text(l10n.save),
        ),
      ],
    );
  }

  Widget _buildConnectionFields(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    String endpointHint;
    if (type == 'openai-api-rest' ||
        type == 'newapi-openai' ||
        type == 'xai-api-rest') {
      endpointHint = l10n.openaiV1Hint;
    } else {
      endpointHint = l10n.googleV1BetaHint;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: type,
          isExpanded: true,
          items: [
            DropdownMenuItem(
                value: 'openai-api-rest', child: Text(l10n.protocolOpenAI)),
            DropdownMenuItem(
                value: 'google-genai-rest', child: Text(l10n.protocolGoogle)),
            const DropdownMenuItem(
                value: 'official-google-genai-api',
                child: Text('Official Google GenAI API (Deprecated)')),
            DropdownMenuItem(
                value: 'newapi-openai', child: Text(l10n.providerNewApiOpenAI)),
            DropdownMenuItem(
                value: 'newapi-gemini', child: Text(l10n.providerNewApiGemini)),
            DropdownMenuItem(
                value: 'xai-api-rest', child: Text(l10n.protocolXai)),
          ],
          onChanged: (v) => setState(() => type = v!),
          decoration: InputDecoration(
            labelText: l10n.channelType,
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.category_outlined, size: 20),
          ),
          // The style applies to the popup menu items too — it must carry an
          // explicit color or the items render with the wrong default.
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: epCtrl,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: l10n.endpointUrl,
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.link, size: 20),
            helperText: endpointHint,
            helperMaxLines: 3,
            helperStyle: TextStyle(color: colorScheme.outline, fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        ApiKeyField(
          controller: keyCtrl,
          label: l10n.apiKey,
          onChanged: (v) {},
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          title: Text(l10n.enableDiscovery, style: const TextStyle(fontSize: 14)),
          subtitle: Text(
            l10n.enableDiscoveryDesc,
            style: TextStyle(fontSize: 12, color: colorScheme.outline),
          ),
          value: discovery,
          onChanged: (v) => setState(() => discovery = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ],
    );
  }
}
