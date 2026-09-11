import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/model_capabilities.dart';
import '../../services/llm/vendors/vendors.dart';
import 'model_edit_controls.dart';
import 'protocol_section_form.dart';
import 'wire_protocol_labels.dart';

/// A model kind (`llm_models.tag`) as the user reads it.
String modelKindLabel(AppLocalizations l10n, String tag) {
  switch (tag) {
    case 'image':
      return l10n.kindImage;
    case 'video':
      return l10n.kindVideo;
    case 'multimodal':
      return l10n.kindMultimodal;
    default:
      return l10n.kindChat;
  }
}

/// The parameter names a capability table puts in front of the user, in the
/// words the workbench's own panels use — what the 「参数」 row promises.
///
/// Video always leads with the two controls the video panel draws for every
/// model (resolution and aspect ratio), which a table does not list; images
/// only have what their table declares. The reference-image ceiling is named
/// last, and only when there is one.
List<String> paramSourceNames(
    AppLocalizations l10n, ModelCapabilities caps, Surface surface) {
  final video = surface == Surface.videoJob;
  final names = <String>[if (video) l10n.resolution, if (video) l10n.aspectRatio];
  for (final spec in video ? caps.videoParams : caps.imageParams) {
    final name = _paramName(l10n, spec.labelKey, video);
    if (name != null && !names.contains(name)) names.add(name);
  }
  final ceiling = caps.maxReferenceImages;
  if (names.isNotEmpty && ceiling != null && ceiling > 0) {
    names.add(l10n.protocolParamReferenceLimit);
  }
  return names;
}

/// The chips of the parameter summary under the request method (D1c `1a`,
/// `1c`): each parameter with the value it starts at, in the surface's fixed
/// order — video always opens with resolution and aspect ratio — and the
/// reference-image ceiling last.
///
/// Read from the capability table the dispatcher resolves for the form as it
/// stands, so a pin on the Images API lists the Images API's parameters.
List<String> paramSummaryItems(
    AppLocalizations l10n, ModelCapabilities caps, Surface surface) {
  final video = surface == Surface.videoJob;
  final seen = <String>{if (video) l10n.resolution, if (video) l10n.aspectRatio};
  final items = <String>[...seen];
  for (final spec in video ? caps.videoParams : caps.imageParams) {
    final name = _paramName(l10n, spec.labelKey, video);
    if (name == null || !seen.add(name)) continue;
    items.add(spec.defaultValue.isEmpty ? name : '$name: ${spec.defaultValue}');
  }
  final ceiling = caps.maxReferenceImages;
  if (ceiling != null && ceiling > 0) {
    items.add('${l10n.protocolParamReferenceLimit} ≤ $ceiling');
  }
  return items;
}

String? _paramName(AppLocalizations l10n, String labelKey, bool video) => switch (labelKey) {
      'resolution' => video ? l10n.resolution : l10n.imageSizeLabel,
      'aspectRatio' => l10n.aspectRatio,
      'quality' => l10n.quality,
      'videoSeconds' => l10n.videoSeconds,
      'promptExtend' => l10n.promptExtend,
      _ => null,
    };

/// The model editor's 「请求方式 · 接口协议」 section (spec D1c `1a`, `1b`,
/// `1e`).
///
/// Takes one of the shapes [protocolSectionForm] decides; the dialog owns the
/// state (the stored selection, the kind) and hands both down, so this widget
/// only draws. Four states:
///
/// 1. **Auto** — 「Auto · resolves to …」 in the field, a helper line, the
///    parameter summary.
/// 2. **Pinned** — the protocol's name with a `primary` stroke, 「改回自动」
///    right-aligned under it, no helper sentence.
/// 3. **Unrecognised id** — Auto, the parameters, an info notice.
/// 4. **No interface** — an error notice in the field's place.
class ModelProtocolSection extends StatelessWidget {
  const ModelProtocolSection({
    super.key,
    required this.header,
    required this.menu,
    required this.form,
    required this.channelFamily,
    required this.kind,
    required this.modelName,
    required this.stored,
    required this.activePin,
    required this.pinIsStale,
    required this.paramsCapabilities,
    required this.onChanged,
  });

  /// The section heading, drawn by the dialog so every section's matches.
  final Widget header;
  final ProtocolMenu menu;
  final ProtocolSectionForm form;
  final ProtocolFamily channelFamily;

  /// The model's kind as the form currently has it.
  final String kind;

  /// Named in the phone's bottom sheet, so it says which model it is choosing
  /// for once it covers the form.
  final String modelName;

  /// The raw stored selection, stale or not — the stale sentence names it.
  final String? stored;

  /// The selection when it is valid on [menu]; null for auto.
  final WireProtocol? activePin;
  final bool pinIsStale;

  /// The capability table the model will have as the form stands: what the
  /// parameter summary describes.
  final ModelCapabilities paramsCapabilities;

  /// Null means auto.
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (form == ProtocolSectionForm.none) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final metrics = ModelEditMetrics.of(context);
    final pin = activePin;
    final effective = pin ?? menu.auto;

    final Widget field = switch (form) {
      ProtocolSectionForm.none => const SizedBox.shrink(),
      // ④: nothing to choose — the field says 「不可用」 and opens nothing,
      // and the reason follows in the error tone.
      ProtocolSectionForm.notice => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ModelEditUnavailableField(),
            const SizedBox(height: AppSpace.s6),
            ModelEditNotice(
              tone: ModelEditTone.error,
              text: l10n.protocolNoSurface(
                  protocolFamilyFormatName(channelFamily), modelKindLabel(l10n, kind)),
            ),
          ],
        ),
      ProtocolSectionForm.readOnly => _readOnly(context, l10n),
      ProtocolSectionForm.dropdown =>
        metrics.phone ? _phoneField(context, l10n) : _desktopField(context, l10n),
    };

    final helper = _helper(l10n);
    final unrecognized = _unrecognizedNotice(l10n);
    final caveat = effective == null || form == ProtocolSectionForm.notice
        ? null
        : wireProtocolCaveat(l10n, effective, channelFamily);
    final showParams = menu.surface != Surface.chat &&
        effective != null &&
        form != ProtocolSectionForm.notice;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: AppSpace.s6),
        field,
        if (form == ProtocolSectionForm.dropdown && pin != null)
          ModelEditBackToAuto(onPressed: () => onChanged(null)),
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (helper != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s6),
                  child: ModelEditHelperText(helper),
                ),
              if (showParams)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s10),
                  child: ModelEditParamBlock(
                    items: paramSummaryItems(l10n, paramsCapabilities, menu.surface),
                  ),
                ),
              if (unrecognized != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s10),
                  child: ModelEditNotice(tone: ModelEditTone.info, text: unrecognized),
                ),
              if (caveat != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.s10),
                  child: ModelEditNotice(tone: ModelEditTone.warning, text: caveat),
                ),
              const SizedBox(width: double.infinity),
            ],
          ),
        ),
      ],
    );
  }

  /// The line under the field, or null when the field — or a notice — says
  /// it already.
  String? _helper(AppLocalizations l10n) {
    final stored = this.stored;
    if (pinIsStale && stored != null) {
      // A stale selection and its kind twin: helper tone, not a warning —
      // the model still runs, on auto.
      final name = storedProtocolLabel(l10n, stored);
      final parsed = WireProtocol.tryParse(stored);
      return parsed != null && parsed.surface != menu.surface
          ? l10n.protocolStaleKindHelper(modelKindLabel(l10n, kind), name)
          : l10n.protocolStaleHelper(name);
    }
    // Pinned: the field names the choice and 「改回自动」 sits under it, so
    // there is nothing left to explain (`1b` ②).
    if (activePin != null || form != ProtocolSectionForm.dropdown) return null;
    final auto = menu.auto;
    if (auto == null) return null;
    if (_unrecognizedNotice(l10n) != null) return null;
    if (wireProtocolCaveat(l10n, auto, channelFamily) != null) return null;
    return l10n.protocolAutoHelper;
  }

  /// `1b` ③: an id that does not corroborate its kind rides the channel's
  /// default for it. Said once, as an info notice, while on auto.
  String? _unrecognizedNotice(AppLocalizations l10n) {
    if (activePin != null || pinIsStale) return null;
    final auto = menu.auto;
    if (auto == null || menu.surface == Surface.chat || menu.recognized) return null;
    final single = l10n.protocolUnrecognizedSingle(wireProtocolLabel(l10n, auto));
    if (form == ProtocolSectionForm.readOnly) return single;
    final alternative = menu.options.where((p) => p != auto).firstOrNull;
    return alternative == null
        ? single
        : l10n.protocolUnrecognizedAuto(wireProtocolLabel(l10n, alternative));
  }

  Widget _leadingIcon(BuildContext context) => Icon(
        activePin != null ? Icons.route : Icons.auto_awesome,
        size: AppSize.iconMd,
        color: Theme.of(context).colorScheme.primary,
      );

  /// `1a`: 「Auto」 at 500, then the resolution in mono and the secondary ink.
  ///
  /// The string is one translated sentence; it is split where it begins with
  /// the Auto label, which is how every locale writes it, and drawn whole in
  /// one style otherwise.
  Widget _autoFace(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final auto = menu.auto;
    final prefix = l10n.protocolAuto;
    final resolved =
        auto == null ? null : l10n.protocolAutoResolved(wireProtocolLabel(l10n, auto));
    final spans = resolved != null && resolved.startsWith(prefix)
        ? [
            TextSpan(text: prefix),
            TextSpan(
              text: resolved.substring(prefix.length),
              style: theme.textTheme.bodySmall?.mono.copyWith(
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ]
        : [TextSpan(text: resolved ?? prefix)];

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
    );
  }

  Widget _desktopField(BuildContext context, AppLocalizations l10n) {
    final textTheme = Theme.of(context).textTheme;
    final auto = menu.auto;
    final pin = activePin;

    return ModelEditMenuField<String>(
      emphasis: pin != null ? ModelEditFieldEmphasis.accent : ModelEditFieldEmphasis.normal,
      leading: _leadingIcon(context),
      // '' stands in for auto. A stale stored value also *displays* as auto
      // (that is how it routes); the helper line says why.
      selected: pin?.id ?? '',
      onSelected: (v) => onChanged(v.isEmpty ? null : v),
      entries: [
        ModelEditMenuEntry(
          value: '',
          label: l10n.protocolAuto,
          description:
              auto == null ? null : l10n.protocolAutoMenuDesc(wireProtocolLabel(l10n, auto)),
        ),
        for (final p in menu.options)
          ModelEditMenuEntry(
            value: p.id,
            label: wireProtocolLabel(l10n, p),
            description: wireProtocolDescription(l10n, p),
            trailing: wireProtocolPath(p, channelFamily),
          ),
      ],
      child: pin != null
          ? Text(
              wireProtocolLabel(l10n, pin),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            )
          : _autoFace(context, l10n),
    );
  }

  /// One route for a model its id does not identify. The user needs to see
  /// how it will be sent, but a control that cannot open would say something
  /// is broken — so it is a line in the field's place.
  Widget _readOnly(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    // A read-only menu has exactly one option, and auto is always one of the
    // options, so it is never null here.
    final auto = menu.auto!;

    return Row(
      children: [
        _leadingIcon(context),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: l10n.protocolSendVia(wireProtocolLabel(l10n, auto)),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: l10n.protocolOnlyOneWay,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  /// `1e`: a two-line card opening a bottom sheet — the name, and under it
  /// the endpoint path once pinned.
  Widget _phoneField(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final auto = menu.auto;
    final pin = activePin;
    final title = pin != null
        ? wireProtocolLabel(l10n, pin)
        : (auto == null
            ? l10n.protocolAuto
            : l10n.protocolAutoResolved(wireProtocolLabel(l10n, auto)));
    final path = pin == null ? null : wireProtocolPath(pin, channelFamily);

    return ModelEditMenuField<String>(
      autoHeight: true,
      emphasis: pin != null ? ModelEditFieldEmphasis.accent : ModelEditFieldEmphasis.normal,
      leading: _leadingIcon(context),
      onTap: () => _openSheet(context, l10n),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          if (path != null)
            Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.mono
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Future<void> _openSheet(BuildContext context, AppLocalizations l10n) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _ProtocolSheet(
        menu: menu,
        channelFamily: channelFamily,
        selected: activePin?.id ?? '',
        title: l10n.interfaceProtocol,
        subtitle: '$modelName · ${modelKindLabel(l10n, kind)}',
      ),
    );
    // The dialog may have closed while the sheet was up.
    if (picked == null || !context.mounted) return;
    onChanged(picked.isEmpty ? null : picked);
  }
}

/// A request method as a model card carries it: the pinned protocol as a
/// tinted chip, or the resolution with an 「· 自动」 suffix, so a row that
/// follows the channel reads apart from one the user set.
class ProtocolPreviewValue extends StatelessWidget {
  const ProtocolPreviewValue({super.key, required this.menu, required this.activePin});

  final ProtocolMenu menu;
  final WireProtocol? activePin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final pin = activePin;
    if (pin != null) {
      final label = wireProtocolLabel(l10n, pin);
      return Tooltip(
        message: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          constraints: const BoxConstraints(maxWidth: 128),
          decoration: BoxDecoration(
            color: colorScheme.accentTint,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.onAccentTint,
            ),
          ),
        ),
      );
    }

    final auto = menu.auto;
    if (auto == null) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: wireProtocolLabel(l10n, auto)),
        TextSpan(
          text: ' ${l10n.protocolAutoSuffix}',
          style: TextStyle(color: colorScheme.outline, fontWeight: FontWeight.w400),
        ),
      ]),
      textAlign: TextAlign.end,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
    );
  }
}

/// The phone's bottom sheet: the same entries as the desktop menu, word for
/// word, with the path at the end of each row.
///
/// Rows carry a radio glyph rather than being `RadioListTile`s: the
/// `groupValue` API is deprecated, and the sheet closes on the tap anyway, so
/// there is no group state to manage.
class _ProtocolSheet extends StatelessWidget {
  const _ProtocolSheet({
    required this.menu,
    required this.channelFamily,
    required this.selected,
    required this.title,
    required this.subtitle,
  });

  final ProtocolMenu menu;
  final ProtocolFamily channelFamily;

  /// The selected value, '' for auto.
  final String selected;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final auto = menu.auto;

    Widget option(String value, String label, String? description, String? path) {
      final isSelected = value == selected;
      return ListTile(
        minTileHeight: AppSize.touch,
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: AppSize.iconLg,
          color: isSelected ? colorScheme.primary : colorScheme.outline,
        ),
        title: Text(label, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        subtitle: description == null
            ? null
            : Text(description,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        trailing: path == null
            ? null
            : Text(path, style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline)),
        onTap: () => Navigator.pop(context, value),
      );
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleMedium),
                Text(subtitle,
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          option(
            '',
            l10n.protocolAuto,
            auto == null ? null : l10n.protocolAutoMenuDesc(wireProtocolLabel(l10n, auto)),
            null,
          ),
          for (final p in menu.options)
            option(
              p.id,
              wireProtocolLabel(l10n, p),
              wireProtocolDescription(l10n, p),
              wireProtocolPath(p, channelFamily),
            ),
        ],
      ),
    );
  }
}
