import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../app_dialog.dart';
import '../app_text_field.dart';
import 'channel_provider_presets.dart';

/// What the picker hands back: a preset and, for the three that have more
/// than one way in, which one was chosen.
class ChannelPresetChoice {
  final ChannelProviderPreset preset;
  final ChannelProviderVariant? variant;

  const ChannelPresetChoice(this.preset, this.variant);
}

/// The provider catalogue as an overlay, for the channel editor's
/// "change preset" button.
///
/// Deliberately the *same* catalogue the add-channel dialog renders in its
/// rail — [kChannelProviderPresets] — rather than a second list kept in step
/// with it by hand. The editor's own hand-written list of channel types is
/// exactly what let DashScope be offered when adding a channel and be missing
/// when editing one (spec D2 `16e`).
Future<ChannelPresetChoice?> showChannelPresetPicker(
  BuildContext context, {
  required AppLocalizations l10n,
}) {
  return AppDialog.show<ChannelPresetChoice>(
    context,
    title: l10n.changePreset,
    subtitle: l10n.changePresetOverlayHint,
    maxWidth: 460,
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

  /// The preset whose variant switch is open, if any. Picking a provider with
  /// more than one face cannot commit immediately — which face decides both
  /// the stored type and the endpoint — so the row expands in place rather
  /// than closing the overlay on a choice only half made.
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
      width: 420,
      height: 460,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _searchCtrl,
            hint: l10n.searchProvidersAlias,
            prefixIcon: const Icon(Icons.search, size: AppSize.iconMd),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(
                      l10n.noProviderMatch,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ...() {
                        final widgets = <Widget>[];
                        for (final group in ChannelProviderGroup.values) {
                          final inGroup =
                              matches.where((p) => p.group == group).toList();
                          if (inGroup.isEmpty) continue;
                          widgets.add(_buildHeading(l10n, group,
                              isFirst: widgets.isEmpty));
                          for (final preset in inGroup) {
                            widgets.add(_buildRow(l10n, preset));
                          }
                        }
                        return widgets;
                      }(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeading(
    AppLocalizations l10n,
    ChannelProviderGroup group, {
    required bool isFirst,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(top: isFirst ? 0 : 4),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 5),
      decoration: isFirst
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            channelProviderGroupLabel(l10n, group),
            style: (isFirst ? theme.textTheme.labelLarge : theme.textTheme.labelMedium)
                ?.copyWith(
              fontWeight: isFirst ? FontWeight.w700 : FontWeight.w600,
              color: isFirst
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              channelProviderGroupHint(l10n, group),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(AppLocalizations l10n, ChannelProviderPreset preset) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isExpanded = _expandedId == preset.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => preset.hasVariants
              ? setState(() => _expandedId = isExpanded ? null : preset.id)
              : _pick(preset, null),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(preset.icon,
                    size: AppSize.iconMd, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    channelProviderTitle(l10n, preset.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                if (preset.hasVariants)
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: AppSize.iconSm,
                    color: colorScheme.onSurfaceVariant,
                  )
                else
                  Text(
                    channelProviderNeedLabel(l10n, preset.need),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: preset.need == ChannelProviderNeed.keyless
                          ? context.semantic.onSuccessContainer
                          : colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 2, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final variant in preset.variants)
                  InkWell(
                    onTap: () => _pick(preset, variant),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        channelProviderVariantLabel(l10n, preset.id, variant.id),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
