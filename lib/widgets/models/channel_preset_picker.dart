import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/llm/vendors/vendors.dart';
import '../app_dialog.dart';
import 'channel_form_sections.dart';
import 'channel_provider_presets.dart';
import 'channel_provider_row.dart';

/// What the picker hands back: a preset and, for the three that have more
/// than one way in, which one was chosen.
class ChannelPresetChoice {
  final ChannelProviderPreset preset;
  final ChannelProviderVariant? variant;

  const ChannelPresetChoice(this.preset, this.variant);
}

/// The provider catalogue as an overlay, for the channel editor's "Change
/// preset" button and the setup wizard's provider field.
///
/// Deliberately the *same* catalogue — and the same rows — the add-channel
/// wizard renders on its first step, [kChannelProviderPresets], rather than a
/// second list kept in step with it by hand. The editor's own hand-written
/// list of channel types is exactly what let DashScope be offered when adding
/// a channel and be missing when editing one.
Future<ChannelPresetChoice?> showChannelPresetPicker(
  BuildContext context, {
  required AppLocalizations l10n,
}) {
  return AppDialog.show<ChannelPresetChoice>(
    context,
    icon: Icons.swap_horiz,
    title: l10n.changePreset,
    subtitle: l10n.changePresetOverlayHint,
    maxWidth: 520,
    onClose: () => Navigator.pop(context),
    content: _ChannelPresetPicker(l10n: l10n),
  );
}

class _ChannelPresetPicker extends StatefulWidget {
  final AppLocalizations l10n;

  const _ChannelPresetPicker({required this.l10n});

  @override
  State<_ChannelPresetPicker> createState() => _ChannelPresetPickerState();
}

class _ChannelPresetPickerState extends State<_ChannelPresetPicker> {
  final TextEditingController _searchCtrl = TextEditingController();

  /// The preset whose variants are open, if any. Picking a provider with more
  /// than one face cannot commit immediately — which face decides both the
  /// stored type and the endpoint — so the row opens in place rather than
  /// closing the overlay on a choice only half made.
  String? _expandedId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ChannelProviderPreset> get _matches {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return kChannelProviderPresets;
    return kChannelProviderPresets.where((p) {
      final haystack = [
        p.id,
        p.channelType,
        channelProviderTitle(widget.l10n, p.id),
        ...p.searchAliases,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _pick(ChannelProviderPreset preset, ChannelProviderVariant? variant) {
    Navigator.pop(context, ChannelPresetChoice(preset, variant));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final matches = _matches;

    return SizedBox(
      width: double.infinity,
      height: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChannelField(
            controller: _searchCtrl,
            hint: l10n.searchProvidersAlias,
            prefixIcon: Icons.search,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpace.s10),
          Expanded(
            child: matches.isEmpty
                ? ChannelProviderNoMatch(
                    l10n: l10n,
                    query: _searchCtrl.text.trim(),
                    onUseCustom: () =>
                        _pick(channelFallbackCustomPreset(), null),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: _buildRows(l10n, matches),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRows(
    AppLocalizations l10n,
    List<ChannelProviderPreset> matches,
  ) {
    final widgets = <Widget>[];
    for (final group in ChannelProviderGroup.values) {
      final inGroup = matches.where((p) => p.group == group).toList();
      if (inGroup.isEmpty) continue;
      // "First" is the first group *rendered*, so a filtered list does not
      // leave a gap above whichever group survived the search.
      widgets.add(ChannelProviderGroupCaption(
        l10n: l10n,
        group: group,
        count: inGroup.length,
        first: widgets.isEmpty,
      ));
      for (final preset in inGroup) {
        widgets.addAll(_buildRow(l10n, preset));
      }
    }
    return widgets;
  }

  List<Widget> _buildRow(AppLocalizations l10n, ChannelProviderPreset preset) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isExpanded = _expandedId == preset.id;

    return [
      ChannelProviderRow(
        l10n: l10n,
        preset: preset,
        selected: isExpanded,
        onTap: () => preset.hasVariants
            ? setState(() => _expandedId = isExpanded ? null : preset.id)
            : _pick(preset, null),
        trailing: preset.hasVariants
            ? Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                size: AppSize.iconMd,
                color: isExpanded
                    ? colorScheme.onAccentTint
                    : colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      if (isExpanded)
        Padding(
          // Under the name, past the avatar: the variants belong to the row.
          padding: const EdgeInsets.fromLTRB(38, 0, 0, AppSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final variant in preset.variants)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _pick(preset, variant),
                    child: SizedBox(
                      height: AppSize.control,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.s10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                channelProviderVariantLabel(
                                    l10n, preset.id, variant.id),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: colorScheme.onSurface),
                              ),
                            ),
                            const SizedBox(width: AppSpace.s10),
                            Text(
                              protocolFamilyLabel(
                                l10n,
                                Vendors.byId(variant.channelType).family,
                              ),
                              style: theme.textTheme.labelSmall?.mono
                                  .copyWith(color: colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }
}
