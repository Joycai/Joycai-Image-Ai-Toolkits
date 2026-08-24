import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../services/llm/channel_probe_service.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../api_key_field.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import 'channel_avatar.dart';
import 'channel_form_sections.dart';
import 'model_tag_chip.dart';

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

  bool _probing = false;
  String? _probeMessage;
  bool? _probeOk;

  @override
  void initState() {
    super.initState();
    final channel = widget.channel;
    nameCtrl = TextEditingController(text: channel?.displayName ?? '');
    epCtrl = TextEditingController(text: channel?.endpoint ?? '');
    keyCtrl = TextEditingController(text: channel?.apiKey ?? '');
    tagCtrl = TextEditingController(text: channel?.tag ?? '');

    type = channel?.type ?? Vendors.googleRest;
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
            AppButton(
              label: l10n.save,
              variant: AppButtonVariant.text,
              onPressed: _save,
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
    return AppDialog(
      icon: Icons.edit_note,
      title: l10n.editChannel,
      // Which channel is being edited belongs under the heading, not trailing
      // it: as a Spacer'd tail it collided with a long title at narrow widths.
      subtitle: widget.channel?.displayName,
      onClose: () => Navigator.pop(context),
      // `15a` separates the heading from the form by spacing alone, same as
      // the model editor's narrow layout; the footer keeps its rule.
      dividedHeading: false,
      maxWidth: 680,
      clipBehavior: Clip.antiAlias,
      // The body brings its own padding so its two columns can carry the
      // divider between them right to the edges.
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
          // 20 horizontal, matching the shell's own inset so the section
          // labels share the heading's left edge — it was 24, and the 4px
          // stagger read as sloppiness, same as the model editor's had.
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          // No IntrinsicHeight here: the appearance column contains a Wrap,
          // whose intrinsic height is computed as a single run — under a
          // tight intrinsic-derived height it overflows once it actually
          // wraps. The divider is drawn as the left column's right border
          // instead of a VerticalDivider (which needs a bounded height).
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(120),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ChannelSectionLabel(l10n.stepConnection),
                      _buildConnectionFields(l10n),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
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
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    _buildListPreview(l10n),
                  ],
                ),
              ),
            ],
          ),
        ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.save,
          icon: Icons.save,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildConnectionFields(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;

    // Reads the vendor registry rather than re-listing channel-type strings:
    // the literals here silently stopped covering new types every time one
    // was added, and an unlisted type fell through to the Gemini hint.
    final String endpointHint = switch (Vendors.byId(type).family) {
      ProtocolFamily.gemini => l10n.googleV1BetaHint,
      ProtocolFamily.anthropic => l10n.anthropicV1Hint,
      ProtocolFamily.openai || ProtocolFamily.midjourney => l10n.openaiV1Hint,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChannelLabelledField(
          l10n.channelType,
          child: DropdownButtonFormField<String>(
          initialValue: type,
          isExpanded: true,
          items: [
            DropdownMenuItem(
                value: Vendors.openAIRest, child: Text(l10n.protocolOpenAI)),
            DropdownMenuItem(
                value: Vendors.googleRest, child: Text(l10n.protocolGoogle)),
            const DropdownMenuItem(
                value: Vendors.officialGoogle,
                child: Text('Official Google GenAI API (Deprecated)')),
            DropdownMenuItem(
                value: Vendors.anthropicRest,
                child: Text(l10n.protocolAnthropic)),
            DropdownMenuItem(
                value: Vendors.newApiOpenAI,
                child: Text(l10n.providerNewApiOpenAI)),
            DropdownMenuItem(
                value: Vendors.newApiGemini,
                child: Text(l10n.providerNewApiGemini)),
            DropdownMenuItem(
                value: Vendors.newApiAnthropic,
                child: Text(l10n.providerNewApiAnthropic)),
            DropdownMenuItem(
                value: Vendors.minimaxAnthropic,
                child: Text(l10n.providerMiniMaxAnthropic)),
            DropdownMenuItem(
                value: Vendors.xaiApi, child: Text(l10n.protocolXai)),
            // The list has to name *every* vendor, not just the ones worth
            // switching to: the dropdown asserts that its current value is
            // among the items, so a channel of an unlisted type could not be
            // opened for editing at all.
            const DropdownMenuItem(
                value: Vendors.deepseek, child: Text('DeepSeek')),
            const DropdownMenuItem(
                value: Vendors.minimax, child: Text('MiniMax')),
            DropdownMenuItem(
                value: Vendors.midjourneyProxy,
                child: Text(l10n.protocolMidjourney)),
          ],
          onChanged: (v) => setState(() => type = v!),
          decoration: const InputDecoration(
            // The spec's glyph is a hexagon — a wire format as a package
            // shape — not Material's circle-square-triangle "category".
            prefixIcon: Icon(Icons.hexagon_outlined, size: 20),
          ),
          // The style applies to the popup menu items too — it must carry an
          // explicit color or the items render with the wrong default.
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
          ),
        ),
        const SizedBox(height: 12),
        ChannelLabelledField(
          l10n.endpointUrl,
          child: TextField(
            controller: epCtrl,
            // Mono: an endpoint is a URL the wire sees verbatim, and `15a`
            // sets it apart from prose the same way the model id is.
            style: Theme.of(context).textTheme.bodyMedium?.mono,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.link, size: 20),
              helperText: endpointHint,
              helperMaxLines: 3,
              helperStyle: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ChannelLabelledField(
          l10n.apiKey,
          child: ApiKeyField(
            controller: keyCtrl,
            onChanged: (v) {},
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          title: Text(l10n.enableDiscovery, style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(
            l10n.enableDiscoveryDesc,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          value: discovery,
          onChanged: (v) => setState(() => discovery = v),
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          dense: true,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            AppButton(
              // The gauge, not the generic network glyph: `15a`/`15b` draw the
              // probe as a speedometer — a measurement, not a status.
              label: l10n.probeChannel,
              icon: Icons.speed,
              variant: AppButtonVariant.text,
              onPressed: _probing ? null : _runProbe,
            ),
            if (_probing) ...[
              const SizedBox(width: 8),
              const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        if (_probeMessage != null) _buildProbeReceipt(context),
      ],
    );
  }

  /// The probe's receipt line: a leading verdict glyph and the message in the
  /// verdict's colour — success green (the semantic role, not the accent),
  /// error red, or muted for "this type has no probe".
  Widget _buildProbeReceipt(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color color = _probeOk == true
        ? context.semantic.success
        : (_probeOk == false ? colorScheme.error : colorScheme.outline);
    final IconData icon = _probeOk == true
        ? Icons.check
        : (_probeOk == false ? Icons.close : Icons.info_outline);

    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _probeMessage!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// `15a`'s closing element: the channel exactly as its row will render in
  /// the models screen's list — disc, name, tag chip — so the three fields
  /// above it are previewed as the one thing they actually produce.
  Widget _buildListPreview(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = nameCtrl.text.trim();
    final tag = tagCtrl.text.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colorScheme.surfaceContainerHigh),
      ),
      child: Row(
        children: [
          if (tag.isNotEmpty)
            TagAvatar(tag, color: Color(tagColor), size: 28)
          else
            Icon(Icons.cloud_queue, size: 22, color: colorScheme.outline),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              name.isEmpty ? l10n.displayName : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: name.isEmpty ? colorScheme.outline : null,
              ),
            ),
          ),
          if (tag.isNotEmpty) ...[
            const SizedBox(width: 8),
            ModelTagChip(tag, color: Color(tagColor), uppercase: false),
          ],
          const Spacer(),
          Text(
            l10n.previewInList,
            style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }

  /// Probes with the *form's current values* — the whole point is testing
  /// what the user is about to save, not what is already stored.
  Future<void> _runProbe() async {
    final l10n = widget.l10n;
    setState(() {
      _probing = true;
      _probeMessage = null;
      _probeOk = null;
    });
    final config = LLMModelConfig(
      modelId: ChannelProbeService.probeModelId,
      channelType: type,
      endpoint: epCtrl.text.trim(),
      apiKey: keyCtrl.text.trim(),
    );
    final result = await ChannelProbeService().probe(config);
    if (!mounted) return;
    setState(() {
      _probing = false;
      switch (result.status) {
        case ChannelProbeStatus.ok:
          _probeOk = true;
          _probeMessage =
              '${l10n.probeOk} (${result.modelCount} ${l10n.probeModels})';
        case ChannelProbeStatus.connectedNoModels:
          _probeOk = true;
          _probeMessage = l10n.probeConnectedNoModels;
        case ChannelProbeStatus.authFailed:
          _probeOk = false;
          _probeMessage = l10n.probeAuthFailed;
        case ChannelProbeStatus.notAnApi:
          _probeOk = false;
          _probeMessage = l10n.probeNotAnApi;
        case ChannelProbeStatus.unreachable:
          _probeOk = false;
          _probeMessage =
              '${l10n.probeUnreachable}${result.detail == null ? '' : ' — ${_clip(result.detail!)}'}';
        case ChannelProbeStatus.notSupported:
          _probeOk = null;
          _probeMessage = l10n.probeNotSupported;
      }
    });
  }

  static String _clip(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;
}
