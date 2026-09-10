import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/model_capabilities.dart';
import '../../services/llm/vendors/vendors.dart';
import '../app_dropdown.dart';
import '../app_labelled_field.dart';
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
    final name = switch (spec.labelKey) {
      'resolution' => video ? l10n.resolution : l10n.imageSizeLabel,
      'aspectRatio' => l10n.aspectRatio,
      'quality' => l10n.quality,
      'videoSeconds' => l10n.videoSeconds,
      'promptExtend' => l10n.promptExtend,
      _ => null,
    };
    if (name != null && !names.contains(name)) names.add(name);
  }
  final ceiling = caps.maxReferenceImages;
  if (names.isNotEmpty && ceiling != null && ceiling > 0) {
    names.add(l10n.protocolParamReferenceLimit);
  }
  return names;
}

/// The model editor's 「请求方式」 section (spec D2 18a, D2a 20a–20g, 20j).
///
/// Takes one of the shapes [protocolSectionForm] decides; the dialog owns the
/// state (the stored selection, the kind) and hands both down, so this widget
/// only draws.
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
  /// 「参数」 row describes.
  final ModelCapabilities paramsCapabilities;

  /// Null means auto.
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (form == ProtocolSectionForm.none) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final effective = activePin ?? menu.auto;

    final Widget body = switch (form) {
      ProtocolSectionForm.none => const SizedBox.shrink(),
      // 20e: the heading stays, the body is one sentence. No disabled control
      // and no empty box — there is nothing to choose.
      ProtocolSectionForm.notice => _HelperLine(l10n.protocolNoSurface(
          protocolFamilyFormatName(channelFamily), modelKindLabel(l10n, kind))),
      ProtocolSectionForm.readOnly => _readOnly(context, l10n),
      ProtocolSectionForm.dropdown => Responsive.isMobile(context)
          ? _pickerField(context, l10n)
          : _dropdown(l10n),
    };

    final showParams = effective != null && showsParamSourceRow(menu, form);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 12),
        body,
        AnimatedSize(
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: showParams
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _ParamSourceRow(
                    protocolName: wireProtocolLabel(l10n, effective),
                    names: paramSourceNames(l10n, paramsCapabilities, menu.surface),
                    pinned: activePin != null,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// The line under the control, or null when the control speaks for itself.
  String? _helper(AppLocalizations l10n) {
    final stored = this.stored;
    if (pinIsStale && stored != null) {
      // State ④ and its kind twin ④′: helper tone, not a warning — the model
      // still runs, on auto.
      final name = storedProtocolLabel(l10n, stored);
      final parsed = WireProtocol.tryParse(stored);
      return parsed != null && parsed.surface != menu.surface
          ? l10n.protocolStaleKindHelper(modelKindLabel(l10n, kind), name)
          : l10n.protocolStaleHelper(name);
    }
    // Pinned: the field names the choice and 「改回自动」 sits under it, so
    // there is nothing left to explain (18a ③, 20c). The unrecognized
    // sentence goes with it — the user has answered that question.
    if (activePin != null) return null;

    final auto = menu.auto;
    if (auto == null) return null;
    final caveat = wireProtocolCaveat(l10n, auto, channelFamily);
    if (caveat != null) return caveat;

    if (menu.surface != Surface.chat && !menu.recognized) {
      if (form == ProtocolSectionForm.readOnly) {
        return l10n.protocolUnrecognizedSingle(wireProtocolLabel(l10n, auto));
      }
      final alternative = menu.options.where((p) => p != auto).firstOrNull;
      return alternative == null
          ? null
          : l10n.protocolUnrecognizedAuto(wireProtocolLabel(l10n, alternative));
    }
    return l10n.protocolAutoHelper;
  }

  Widget _dropdown(AppLocalizations l10n) {
    final auto = menu.auto;
    final pin = activePin;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppLabelledField(
          label: l10n.interfaceProtocol,
          child: _PinnedFieldSkin(
            pinned: pin != null,
            // Controlled, so the menu can change with the channel, the id and
            // the kind without the field having to be re-keyed.
            child: AppDropdown<String>(
              // '' stands in for auto. A stale stored value also *displays*
              // as auto (that is how it routes); the helper line says why.
              value: pin?.id ?? '',
              items: [
                // The closed field answers "which one actually runs"; the open
                // menu says why (20g).
                AppDropdownItem(
                  value: '',
                  label: l10n.protocolAuto,
                  selectedLabel: auto == null
                      ? l10n.protocolAuto
                      : l10n.protocolAutoResolved(wireProtocolLabel(l10n, auto)),
                  description: auto == null
                      ? null
                      : l10n.protocolAutoMenuDesc(wireProtocolLabel(l10n, auto)),
                ),
                for (final p in menu.options)
                  AppDropdownItem(
                    value: p.id,
                    label: wireProtocolLabel(l10n, p),
                    description: wireProtocolDescription(l10n, p),
                    trailing: wireProtocolPath(p, channelFamily),
                  ),
              ],
              onChanged: (v) => onChanged(v == null || v.isEmpty ? null : v),
              prefixIcon: Icons.alt_route_outlined,
              helperText: _helper(l10n),
              helperMaxLines: 3,
            ),
          ),
        ),
        if (pin != null) _BackToAuto(onPressed: () => onChanged(null)),
      ],
    );
  }

  /// 20d: one route for a model its id does not identify. The user needs to
  /// see how it will be sent, but a disabled dropdown would say something is
  /// broken — so it is a sentence in the field's place, under the same
  /// caption.
  Widget _readOnly(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    // A read-only menu has exactly one option, and auto is always one of the
    // options, so it is never null here.
    final auto = menu.auto!;
    final helper = _helper(l10n);

    return AppLabelledField(
      label: l10n.interfaceProtocol,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: l10n.protocolSendVia(wireProtocolLabel(l10n, auto)),
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: l10n.protocolOnlyOneWay,
                    style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ),
          ),
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _HelperLine(helper),
            ),
        ],
      ),
    );
  }

  /// 20j: on a phone the choice opens a bottom sheet, and the field grows a
  /// second line — the resolution on auto, the endpoint path once pinned.
  Widget _pickerField(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final auto = menu.auto;
    final pin = activePin;

    final title = pin != null
        ? wireProtocolLabel(l10n, pin)
        : (auto == null
            ? l10n.protocolAuto
            : l10n.protocolAutoResolved(wireProtocolLabel(l10n, auto)));
    final path = pin == null ? null : wireProtocolPath(pin, channelFamily);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppLabelledField(
          label: l10n.interfaceProtocol,
          child: _PinnedFieldSkin(
            pinned: pin != null,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: () => _openSheet(context, l10n),
              child: InputDecorator(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.alt_route_outlined, size: AppSize.iconLg),
                  suffixIcon: Icon(Icons.expand_more, color: colorScheme.outline),
                  helperText: _helper(l10n),
                  helperMaxLines: 3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (path != null)
                      Text(
                        path,
                        style: textTheme.labelSmall?.mono.copyWith(color: colorScheme.outline),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (pin != null) _BackToAuto(onPressed: () => onChanged(null)),
      ],
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

/// The model-card preview's 「请求方式」 value (D2a 20h): the pinned chip
/// exactly as the card will draw it, or the resolution with an 「· 自动」
/// suffix, so the user can tell a row that follows the channel from one they
/// set.
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

/// A helper sentence in the section's own voice. Never a warning colour (18a,
/// D2a).
///
/// `onSurfaceVariant`, the colour Material gives a field's helper line — so a
/// sentence standing in for a field reads exactly like the helper under the
/// dropdown in the neighbouring state. `outline` rendered it a step fainter
/// than that helper, which made the read-only and notice states look disabled.
class _HelperLine extends StatelessWidget {
  const _HelperLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// 18a ③: the pinned field swaps two tokens and nothing else — the border to
/// the accent, the fill to its tint.
///
/// Reads the theme from its *own* context, below the dialog's
/// `FilledFieldScope`. Rebuilding the decoration theme from a context above
/// that scope would drop the fill it adds.
class _PinnedFieldSkin extends StatelessWidget {
  const _PinnedFieldSkin({required this.pinned, required this.child});

  final bool pinned;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!pinned) return child;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final decoration = theme.inputDecorationTheme;
    InputBorder? accent(InputBorder? border) => border is OutlineInputBorder
        ? border.copyWith(borderSide: border.borderSide.copyWith(color: colorScheme.primary))
        : border;

    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: decoration.copyWith(
          fillColor: colorScheme.accentTint,
          border: accent(decoration.border),
          enabledBorder: accent(decoration.enabledBorder),
        ),
      ),
      child: child,
    );
  }
}

/// 18a ③: 「改回自动」, a dense inline action under the pinned field rather
/// than a row of its own.
class _BackToAuto extends StatelessWidget {
  const _BackToAuto({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 28),
        ),
        child: Text(AppLocalizations.of(context)!.protocolBackToAuto),
      ),
    );
  }
}

/// D2a ruling 4: where an unidentified model's parameters come from, in the
/// same container as 18a's explanation row. Neutral on auto, tinted once
/// pinned — the tint follows the choice.
class _ParamSourceRow extends StatelessWidget {
  const _ParamSourceRow({
    required this.protocolName,
    required this.names,
    required this.pinned,
  });

  final String protocolName;
  final List<String> names;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final foreground = pinned ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant;
    final text = names.isEmpty
        ? l10n.protocolParamsNone
        : l10n.protocolParamsDefault(protocolName, names.join(' · '));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: pinned ? colorScheme.accentTint : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: pinned ? colorScheme.accentRing : colorScheme.outlineVariant),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: l10n.protocolParamsLabel,
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: AppType.trackedLabelSpacing,
              color: foreground,
            ),
          ),
          const TextSpan(text: '  '),
          TextSpan(
            text: text,
            style: textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ]),
      ),
    );
  }
}

/// 20j's bottom sheet: the same entries as the desktop menu, word for word,
/// with the path at the end of each row.
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
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 22,
          color: isSelected ? colorScheme.primary : colorScheme.outline,
        ),
        title: Text(label, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
        subtitle: description == null
            ? null
            : Text(description, style: textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
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
                Text(subtitle, style: textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
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
