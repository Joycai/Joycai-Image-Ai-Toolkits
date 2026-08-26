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
import '../app_labelled_field.dart';
import '../app_button.dart';
import '../app_setting_row.dart';
import '../app_dialog.dart';
import '../app_text_field.dart';
import 'channel_avatar.dart';
import 'channel_preset_picker.dart';
import 'channel_form_sections.dart';
import 'channel_provider_presets.dart';
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
    // The preset a stored type came from, so the shortcut bar can say what
    // this channel is sitting on. Null is a real answer, not a failure: a
    // channel created by an older build can carry a type no preset offers.
    _presetId = presetForChannelType(type)?.id;
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

  /// Opens the same catalogue the add-channel dialog uses and applies what
  /// the user picks. One list, two dialogs: the editor used to keep its own
  /// hand-written list of types, which is how DashScope came to be offered
  /// in one and missing from the other (spec D2 `16d` note A).
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
      _probeMessage = null;
      _probeOk = null;
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
        body: FilledFieldScope(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Above the sections on the phone too (spec D2 `16e`): the
                // preset describes the whole channel, not its connection half.
                _buildPresetBar(l10n),
                const SizedBox(height: 16),
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
      content: FilledFieldScope(
        child: SingleChildScrollView(
          // 20 horizontal, matching the shell's own inset so the section
          // labels share the heading's left edge — it was 24, and the 4px
          // stagger read as sloppiness, same as the model editor's had.
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPresetBar(l10n),
              const SizedBox(height: 16),
              // No IntrinsicHeight here: the appearance column contains a
              // Wrap, whose intrinsic height is computed as a single run —
              // under a tight intrinsic-derived height it overflows once it
              // actually wraps. The divider is drawn as the left column's
              // right border instead of a VerticalDivider (which needs a
              // bounded height).
              Row(
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
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(label: l10n.save, icon: Icons.save, onPressed: _save),
      ],
    );
  }

  /// True when the stored type *is* one of the generic family profiles,
  /// so the protocol dropdown already lists it and needs no extra entry.
  bool get _typeIsGenericFamily =>
      ProtocolFamily.values.any((f) => genericVendorForFamily(f) == type);

  /// Whether this channel's vendor can be saved without a key — the local
  /// runtimes, which have no auth to give.
  bool get _keyOptional => Vendors.byId(type).keyOptional;

  /// The shortcut bar above the connection fields: which preset this channel
  /// matches, whether it has drifted from that preset's address, and a way to
  /// swap presets.
  ///
  /// A shortcut, deliberately not the way in. The fields below stay visible
  /// and editable at all times, so a channel pointed at an international
  /// host or a corporate gateway is edited by changing the address — not by
  /// hunting for a preset that happens to be "right" (spec D2 `16d`).
  Widget _buildPresetBar(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preset = _preset;
    final variant = preset == null ? null : variantForChannelType(preset, type);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.channelPresetLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (preset == null)
                      _buildPresetChip(l10n.presetUnmatched, muted: true)
                    else
                      _buildPresetChip(
                        variant == null
                            ? channelProviderTitle(l10n, preset.id)
                            : '${channelProviderTitle(l10n, preset.id)}'
                                  ' · ${channelProviderVariantLabel(l10n, preset.id, variant.id)}',
                      ),
                    if (_endpointDivergesFromPreset)
                      _buildPresetChip(
                        l10n.presetEndpointModified,
                        warning: true,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  preset == null
                      ? l10n.presetUnmatchedHint
                      : l10n.channelPresetHint,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppButton(
            label: l10n.changePreset,
            icon: Icons.swap_horiz,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.compact,
            onPressed: () => _changePreset(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(
    String label, {
    bool muted = false,
    bool warning = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final Color background;
    final Color foreground;
    if (warning) {
      background = context.semantic.warningContainer;
      foreground = context.semantic.onWarningContainer;
    } else if (muted) {
      background = colorScheme.surfaceContainerHighest;
      foreground = colorScheme.onSurfaceVariant;
    } else {
      background = colorScheme.accentTint;
      foreground = colorScheme.onAccentTint;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
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
      ProtocolFamily.dashscope => l10n.dashscopeApiV1Hint,
      ProtocolFamily.openai || ProtocolFamily.midjourney => l10n.openaiV1Hint,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppLabelledField(
          label: l10n.protocolField,
          child: DropdownButtonFormField<String>(
            initialValue: type,
            isExpanded: true,
            // The four protocol families, plus this channel's own stored type
            // when it is not one of them. The old field mixed protocol and
            // supplier into one list and went stale every time a vendor was
            // added; the supplier now lives in the preset bar above, and this
            // half names only the wire format (spec D2 `16d` note B).
            items: [
              for (final family in ProtocolFamily.values)
                DropdownMenuItem(
                  value: genericVendorForFamily(family),
                  child: Text(protocolFamilyLabel(l10n, family)),
                ),
              // A stored type that is a *specific* supplier — dashscope-api,
              // newapi-gemini, the deprecated official-google-genai-api — has
              // to be representable or the dropdown asserts and the channel
              // cannot be opened at all. It is listed as itself, last.
              if (!_typeIsGenericFamily)
                DropdownMenuItem(
                  value: type,
                  // Named by family *and* supplier: the family alone would read
                  // identically to the generic item above it, and the supplier
                  // alone would hide which wire format this channel speaks.
                  child: Text(
                    [
                      protocolFamilyLabel(l10n, Vendors.byId(type).family),
                      channelTypeLabel(l10n, type),
                      if (isDeprecatedChannelType(type)) l10n.deprecatedLabel,
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() {
              type = v!;
              // Choosing a wire format by hand means this channel is no longer
              // the supplier the preset named, so the bar stops claiming it is.
              _presetId = presetForChannelType(type)?.id;
            }),
            decoration: const InputDecoration(
              // The spec's glyph is a hexagon — a wire format as a package
              // shape — not Material's circle-square-triangle "category".
              prefixIcon: Icon(Icons.hexagon_outlined, size: 20),
            ),
            // The style applies to the popup menu items too — it must carry an
            // explicit color or the items render with the wrong default.
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
          ),
        ),
        const SizedBox(height: 12),
        AppLabelledField(
          label: l10n.endpointUrl,
          child: TextField(
            controller: epCtrl,
            // Mono: an endpoint is a URL the wire sees verbatim, and `15a`
            // sets it apart from prose the same way the model id is.
            style: Theme.of(context).textTheme.bodyMedium?.mono,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.link, size: 20),
              helperText: endpointHint,
              helperMaxLines: 3,
              helperStyle: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colorScheme.outline),
              // Only offered once the address actually differs from the
              // preset's — an always-present "restore" on a field already
              // holding the value it would restore is noise.
              suffixIcon: _endpointDivergesFromPreset
                  ? IconButton(
                      icon: const Icon(Icons.restart_alt, size: 20),
                      tooltip: l10n.restorePresetEndpoint,
                      onPressed: () => setState(() {
                        epCtrl.text = _presetEndpoint!;
                        _probeMessage = null;
                        _probeOk = null;
                      }),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppLabelledField(
          label: _keyOptional
              ? '${l10n.apiKey} · ${l10n.apiKeyOptional}'
              : l10n.apiKey,
          child: ApiKeyField(
            controller: keyCtrl,
            hint: _keyOptional ? l10n.apiKeyLocalPlaceholder : null,
            onChanged: (v) {},
          ),
        ),
        const SizedBox(height: 4),
        AppToggleRow(
          title: l10n.enableDiscovery,
          description: l10n.enableDiscoveryDesc,
          value: discovery,
          onChanged: (v) => setState(() => discovery = v),
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
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
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
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
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
            style: textTheme.labelSmall?.mono.copyWith(
              color: colorScheme.outline,
            ),
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

  static String _clip(String s) =>
      s.length > 160 ? '${s.substring(0, 160)}…' : s;
}
