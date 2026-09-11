import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_channel.dart';
import '../../services/llm/channel_probe_service.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/vendors/vendors.dart';
import '../../state/app_state.dart';
import '../app_button.dart';
import '../app_dialog.dart';
import '../app_dropdown.dart';
import '../app_field_size.dart';
import 'channel_form_sections.dart';
import 'channel_preset_picker.dart';
import 'channel_probe_result_card.dart';
import 'channel_provider_presets.dart';
import 'channel_provider_row.dart';

/// Edit-channel dialog (design `D1b 1e`): the wizard's fields laid flat in
/// four sections — provider preset, basic info, configuration, tag and
/// appearance beside the list preview — in a 760 panel, with Delete at the
/// footer's left and Cancel / Save at its right.
///
/// The preset card is a shortcut, not the way in: the fields below stay
/// visible and editable, so a channel pointed at an international host or a
/// corporate gateway is edited by changing the address, not by hunting for a
/// preset that happens to be "right".
///
/// On a phone the same sections stack in a full-screen page.
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
  ChannelProbeResult? _probe;

  /// Which catalogue preset this channel matches, or null for a type no
  /// preset covers. Presentation only — [type] remains the stored truth.
  String? _presetId;

  @override
  void initState() {
    super.initState();
    final channel = widget.channel;
    nameCtrl = TextEditingController(text: channel?.displayName ?? '');
    epCtrl = TextEditingController(text: channel?.endpoint ?? '');
    keyCtrl = TextEditingController(text: channel?.apiKey ?? '');
    tagCtrl = TextEditingController(text: channel?.tag ?? '');

    type = channel?.type ?? Vendors.googleRest;
    // The preset a stored channel came from. Null is a real answer, not a
    // failure: a channel created by an older build can carry a type no preset
    // offers. The endpoint goes along because the type alone is ambiguous —
    // the official supplier and the "compatible host of your own" preset
    // store the same one, and only the address separates them.
    _presetId = presetForChannelType(type, endpoint: epCtrl.text)?.id;
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

  ChannelProviderPreset? get _preset => _presetId == null
      ? null
      : kChannelProviderPresets.firstWhere((p) => p.id == _presetId);

  /// The endpoint the current preset would supply, or null when it has none
  /// (a relay, whose host is the user's own).
  String? get _presetEndpoint {
    final preset = _preset;
    if (preset == null) return null;
    return variantForChannelType(preset, type)?.defaultEndpoint ??
        preset.defaultEndpoint;
  }

  /// True when this channel points somewhere other than its preset's default
  /// — an international host, a corporate gateway, a relay fronting the same
  /// API. Worth saying out loud, because changing preset would overwrite it.
  bool get _endpointDivergesFromPreset {
    final presetEndpoint = _presetEndpoint;
    return presetEndpoint != null && epCtrl.text.trim() != presetEndpoint;
  }

  /// True when the stored type *is* one of the generic family profiles,
  /// so the protocol dropdown already lists it and needs no extra entry.
  bool get _typeIsGenericFamily =>
      ProtocolFamily.values.any((f) => genericVendorForFamily(f) == type);

  /// Whether this channel's vendor can be saved without a key — the local
  /// runtimes, which have no auth to give.
  bool get _keyOptional => Vendors.byId(type).keyOptional;

  int get _modelCount =>
      widget.appState.getModelsForChannel(widget.channel?.id).length;

  /// Opens the same catalogue the add-channel wizard uses and applies what
  /// the user picks. One list, two dialogs.
  Future<void> _changePreset(AppLocalizations l10n) async {
    final picked = await showChannelPresetPicker(context, l10n: l10n);
    if (picked == null || !mounted) return;
    setState(() {
      _presetId = picked.preset.id;
      type = picked.variant?.channelType ?? picked.preset.channelType;
      final endpoint =
          picked.variant?.defaultEndpoint ?? picked.preset.defaultEndpoint;
      // Key, name and tag are the user's, not the preset's, and survive.
      if (endpoint != null) epCtrl.text = endpoint;
      _probe = null;
    });
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

    if (mounted) Navigator.pop(context);
  }

  /// Delete, confirmed first. Cancel holds focus so Enter never deletes.
  Future<void> _confirmDelete(AppLocalizations l10n) async {
    final channel = widget.channel;
    if (channel?.id == null) return;
    final colorScheme = Theme.of(context).colorScheme;

    final confirmed = await AppDialog.show<bool>(
      context,
      icon: Icons.delete_outline,
      iconColor: colorScheme.error,
      title: l10n.deleteChannel,
      subtitle: channel!.displayName,
      maxWidth: 440,
      content: Text(l10n.deleteChannelConfirm(channel.displayName)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.deleteChannel,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await widget.appState.deleteChannel(channel.id!);
    if (mounted) Navigator.pop(context);
  }

  /// Probes with the *form's current values* — the whole point is testing
  /// what the user is about to save, not what is already stored.
  Future<void> _runProbe() async {
    setState(() {
      _probing = true;
      _probe = null;
    });
    final result = await ChannelProbeService().probe(
      LLMModelConfig(
        modelId: ChannelProbeService.probeModelId,
        channelType: type,
        endpoint: epCtrl.text.trim(),
        apiKey: keyCtrl.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probe = result;
    });
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    if (Responsive.isMobile(context)) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(l10n.editChannel),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
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
          padding: const EdgeInsets.all(AppSpace.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._buildSections(l10n, stacked: true),
              if (widget.channel?.id != null) ...[
                const SizedBox(height: AppSpace.s22),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    label: l10n.deleteChannel,
                    icon: Icons.delete_outline,
                    variant: AppButtonVariant.destructiveText,
                    onPressed: () => _confirmDelete(l10n),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return AppDialog(
      titleWidget: _buildHeader(l10n),
      maxWidth: 760,
      dividedHeading: true,
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.s22, AppSpace.s16, AppSpace.s22, AppSpace.s22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildSections(l10n, stacked: false),
        ),
      ),
      actionsOverride: Row(
        children: [
          if (widget.channel?.id != null)
            AppButton(
              label: l10n.deleteChannel,
              icon: Icons.delete_outline,
              variant: AppButtonVariant.destructiveText,
              onPressed: () => _confirmDelete(l10n),
            ),
          const Spacer(),
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppSpace.s6),
          AppButton(label: l10n.save, onPressed: _save),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    final tag = tagCtrl.text.trim();
    final name = nameCtrl.text.trim();
    return ChannelDialogHeader(
      leading: ChannelIdentityAvatar(
        label: tag.isNotEmpty ? tag : name,
        color: Color(tagColor),
        size: AppSize.touch,
        radius: AppRadius.control,
      ),
      title: l10n.editChannel,
      // Which channel is being edited, under the heading: its stored name and
      // how many models hang off it — what a delete would also take.
      subtitle: widget.channel == null
          ? null
          : '${widget.channel!.displayName} · ${l10n.countModels(_modelCount)}',
      monoSubtitle: true,
      onClose: () => Navigator.pop(context),
    );
  }

  List<Widget> _buildSections(AppLocalizations l10n, {required bool stacked}) {
    return [
      _buildPresetSection(l10n),
      const SizedBox(height: AppSpace.s16),
      _buildBasicSection(l10n, stacked: stacked),
      const SizedBox(height: AppSpace.s16),
      _buildConfigSection(l10n, stacked: stacked),
      const SizedBox(height: AppSpace.s16),
      _pair(
        _buildAppearanceSection(l10n, stacked: stacked),
        _buildPreviewSection(l10n),
        stacked: stacked,
        gap: AppSpace.s22,
      ),
    ];
  }

  /// Two blocks side by side on the dialog, one over the other on a phone.
  Widget _pair(
    Widget first,
    Widget second, {
    required bool stacked,
    double gap = AppSpace.s10,
  }) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, SizedBox(height: gap), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        SizedBox(width: gap),
        Expanded(child: second),
      ],
    );
  }

  // --- Provider preset -------------------------------------------------------

  /// Which preset this channel sits on, whether its address has drifted from
  /// that preset's, and a way to swap presets — with the warning that swapping
  /// overwrites the protocol and address.
  Widget _buildPresetSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preset = _preset;
    final variant = preset == null ? null : variantForChannelType(preset, type);

    final String title = preset == null
        ? l10n.presetUnmatched
        : variant == null
            ? channelProviderTitle(l10n, preset.id)
            : '${channelProviderTitle(l10n, preset.id)}'
                ' · ${channelProviderVariantLabel(l10n, preset.id, variant.id)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelSectionLabel(l10n.channelPresetLabel),
        Container(
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              if (preset == null)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.hexagon_outlined,
                      size: AppSize.iconMd, color: colorScheme.onSurfaceVariant),
                )
              else
                ChannelIdentityAvatar(
                  label: channelProviderTitle(l10n, preset.id),
                  color: channelPresetIdentityColor(preset),
                ),
              const SizedBox(width: AppSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpace.s6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: preset == null
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onSurface,
                          ),
                        ),
                        if (_endpointDivergesFromPreset)
                          ChannelBadge(
                            l10n.presetEndpointModified,
                            tone: ChannelBadgeTone.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset == null
                          ? l10n.presetUnmatchedHint
                          : l10n.presetShortHint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.s10),
              AppButton(
                label: l10n.changePreset,
                icon: Icons.swap_horiz,
                variant: AppButtonVariant.secondary,
                accentLabel: true,
                size: AppButtonSize.compact,
                onPressed: () => _changePreset(l10n),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s6),
        ChannelNoteStrip(l10n.changePresetOverlayHint,
            icon: Icons.warning_amber_rounded),
      ],
    );
  }

  // --- Basic info ------------------------------------------------------------

  Widget _buildBasicSection(AppLocalizations l10n, {required bool stacked}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelSectionLabel(l10n.basicInfo),
        _pair(
          ChannelLabelledField(
            label: l10n.displayName,
            child: ChannelField(
              controller: nameCtrl,
              hint: l10n.nameHint,
              onChanged: (_) => setState(() {}),
            ),
          ),
          ChannelLabelledField(
            label: l10n.tag,
            child: ChannelField(
              controller: tagCtrl,
              mono: true,
              hint: l10n.tagHint,
              onChanged: (_) => setState(() {}),
            ),
          ),
          stacked: stacked,
        ),
      ],
    );
  }

  // --- Configuration ---------------------------------------------------------

  String _familyDescription(AppLocalizations l10n, ProtocolFamily family) =>
      switch (family) {
        ProtocolFamily.openai => l10n.protocolOpenAIDesc,
        ProtocolFamily.gemini => l10n.protocolGoogleDesc,
        ProtocolFamily.anthropic => l10n.protocolAnthropicDesc,
        ProtocolFamily.midjourney => l10n.protocolMidjourneyDesc,
        ProtocolFamily.dashscope => l10n.protocolDashScopeNativeDesc,
      };

  Widget _buildConfigSection(AppLocalizations l10n, {required bool stacked}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Reads the vendor registry rather than re-listing channel-type strings:
    // the literals here silently stopped covering new types every time one
    // was added, and an unlisted type fell through to the Gemini hint.
    final String endpointHint = switch (Vendors.byId(type).family) {
      ProtocolFamily.gemini => l10n.googleV1BetaHint,
      ProtocolFamily.anthropic => l10n.anthropicV1Hint,
      ProtocolFamily.dashscope => l10n.dashscopeApiV1Hint,
      ProtocolFamily.openai || ProtocolFamily.midjourney => l10n.openaiV1Hint,
    };

    final protocolField = Theme(
      // The dropdown takes the same column-coloured fill as the fields beside
      // it; its geometry is AppDropdown's own 32 size.
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colorScheme.surfaceContainerLow,
        ),
      ),
      child: AppDropdown<String>(
        value: type,
        size: AppFieldSize.regular,
        // The protocol families, plus this channel's own stored type when it
        // is not one of them. The supplier lives in the preset card above;
        // this field names only the wire format.
        items: [
          for (final family in ProtocolFamily.values)
            AppDropdownItem(
              value: genericVendorForFamily(family),
              label: protocolFamilyLabel(l10n, family),
              description: _familyDescription(l10n, family),
            ),
          // A stored type that is a *specific* supplier — dashscope-api,
          // newapi-gemini, the deprecated official-google-genai-api — has to
          // be representable or the dropdown asserts and the channel cannot
          // be opened at all. It is listed as itself, last.
          if (!_typeIsGenericFamily)
            AppDropdownItem(
              value: type,
              // Named by family *and* supplier: the family alone would read
              // identically to the generic item above it.
              label: [
                protocolFamilyLabel(l10n, Vendors.byId(type).family),
                channelTypeLabel(l10n, type),
                if (isDeprecatedChannelType(type)) l10n.deprecatedLabel,
              ].join(' · '),
              muted: isDeprecatedChannelType(type),
            ),
        ],
        onChanged: (v) => setState(() {
          type = v!;
          // Choosing a wire format by hand means this channel is no longer
          // the supplier the preset named, unless the address still says so.
          _presetId = presetForChannelType(type, endpoint: epCtrl.text)?.id;
          _probe = null;
        }),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelSectionLabel(l10n.configuration),
        ChannelLabelledField(
          label: l10n.endpointUrl,
          // Only offered once the address actually differs from the preset's
          // — a restore on a field already holding the value is noise.
          trailing: _endpointDivergesFromPreset
              ? AppButton(
                  label: l10n.restorePresetEndpoint,
                  variant: AppButtonVariant.text,
                  size: AppButtonSize.compact,
                  onPressed: () => setState(() {
                    epCtrl.text = _presetEndpoint!;
                    _probe = null;
                  }),
                )
              : null,
          // The preset's own address when there is one — what Restore would
          // put back — and the family's path convention otherwise.
          helper: _presetEndpoint != null
              ? l10n.endpointPresetValue(_presetEndpoint!)
              : endpointHint,
          child: ChannelField(
            controller: epCtrl,
            mono: true,
            onChanged: (_) => setState(() => _probe = null),
          ),
        ),
        const SizedBox(height: AppSpace.s10),
        _pair(
          ChannelLabelledField(
            label: _keyOptional
                ? '${l10n.apiKey} · ${l10n.apiKeyOptional}'
                : l10n.apiKey,
            child: ChannelField(
              controller: keyCtrl,
              mono: true,
              obscurable: true,
              hint: _keyOptional ? l10n.apiKeyLocalPlaceholder : null,
              onChanged: (_) => setState(() => _probe = null),
            ),
          ),
          ChannelLabelledField(
            label: l10n.protocolField,
            child: protocolField,
          ),
          stacked: stacked,
        ),
        const SizedBox(height: AppSpace.s10),
        ChannelToggleCard(
          title: l10n.enableDiscovery,
          description: l10n.discoveryOffEffect,
          value: discovery,
          onChanged: (v) => setState(() => discovery = v),
        ),
        const SizedBox(height: AppSpace.s10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppButton(
            label: l10n.probeChannel,
            icon: Icons.network_check,
            variant: AppButtonVariant.secondary,
            accentLabel: true,
            loading: _probing,
            onPressed: _runProbe,
          ),
        ),
        if (_probe != null) ...[
          const SizedBox(height: AppSpace.s10),
          ChannelProbeResultCard(
            l10n: l10n,
            result: _probe!,
            onRetry: _probing ? null : _runProbe,
          ),
        ],
      ],
    );
  }

  // --- Tag & appearance, list preview ----------------------------------------

  Widget _buildAppearanceSection(AppLocalizations l10n, {required bool stacked}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelSectionLabel(l10n.tagAndAppearance),
        ChannelFieldLabel(l10n.tagColor),
        const SizedBox(height: AppSpace.s4),
        ChannelTagColorPicker(
          l10n: l10n,
          selectedColor: tagColor,
          inlineCount: 8,
          swatchSize: 24,
          onColorChanged: (c) => setState(() => tagColor = c),
        ),
      ],
    );
  }

  /// The channel exactly as its row will render in the models screen's
  /// channel column, so the name, tag and colour above are previewed as the
  /// one thing they actually produce.
  Widget _buildPreviewSection(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChannelSectionLabel(l10n.previewInList),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: ChannelListRowPreview(
            name: nameCtrl.text.trim(),
            namePlaceholder: l10n.displayName,
            tag: tagCtrl.text.trim(),
            color: Color(tagColor),
            subline: l10n.countModels(_modelCount),
          ),
        ),
      ],
    );
  }
}
