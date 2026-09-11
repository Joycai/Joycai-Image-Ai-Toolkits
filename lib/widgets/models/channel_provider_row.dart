import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../app_button.dart';
import 'channel_form_sections.dart';
import 'channel_provider_presets.dart';

/// The identity colour a provider's avatar is drawn in.
///
/// Derived from the preset's place in the catalogue, so it is stable across
/// builds and needs no field on the preset. Only the first eight tag colours
/// are used — the saturated primaries, under which a white initial reads; the
/// extended palette's yellow and lime would not carry one.
Color channelPresetIdentityColor(ChannelProviderPreset preset) {
  const readable = 8;
  final index = kChannelProviderPresets.indexOf(preset);
  return AppConstants.tagColors[(index < 0 ? 0 : index) % readable];
}

/// The preset a search that found nothing falls back to: the first of the
/// custom group, which is the "any host speaking the OpenAI dialect" row.
ChannelProviderPreset channelFallbackCustomPreset() => kChannelProviderPresets
    .firstWhere((p) => p.group == ChannelProviderGroup.custom);

/// A group's caption in the provider list: the tracked group name and a mono
/// count of its rows (`VENDORS 6`).
class ChannelProviderGroupCaption extends StatelessWidget {
  const ChannelProviderGroupCaption({
    super.key,
    required this.l10n,
    required this.group,
    required this.count,
    this.first = false,
  });

  final AppLocalizations l10n;
  final ChannelProviderGroup group;
  final int count;

  /// The first caption rendered sits flush; the rest keep a gap above.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : AppSpace.s10, left: 2),
      child: ChannelSectionLabel(
        channelProviderGroupLabel(l10n, group),
        trailing: Text(
          '$count',
          style: theme.textTheme.labelSmall?.mono
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// One provider in the catalogue (`D1b 1a` 供应商行): a 44 row on the column
/// colour with a hairline, the provider's identity avatar, its name, and the
/// badges that say what picking it leads to — how many ways in it has,
/// whether it is deprecated, and what the next step will ask for.
class ChannelProviderRow extends StatelessWidget {
  const ChannelProviderRow({
    super.key,
    required this.l10n,
    required this.preset,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final AppLocalizations l10n;
  final ChannelProviderPreset preset;
  final bool selected;
  final VoidCallback onTap;

  /// Replaces the requirement badge — the preset picker puts its expand
  /// chevron there for a provider that opens into variants.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = channelProviderTitle(l10n, preset.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s4),
      child: Material(
        color: selected ? colorScheme.accentTint : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AppSize.touch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
              child: Row(
                children: [
                  ChannelIdentityAvatar(
                    label: title,
                    color: channelPresetIdentityColor(preset),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.metricsOnly.copyWith(
                        color: selected
                            ? colorScheme.onAccentTint
                            : colorScheme.onSurface,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (preset.hasVariants) ...[
                    const SizedBox(width: AppSpace.s6),
                    ChannelBadge(
                      l10n.providerVariantCount(preset.variants.length),
                      mono: true,
                      onTint: selected,
                    ),
                  ],
                  if (isDeprecatedChannelType(preset.channelType)) ...[
                    const SizedBox(width: AppSpace.s6),
                    ChannelBadge(
                      l10n.deprecatedLabel,
                      tone: ChannelBadgeTone.warning,
                    ),
                  ],
                  const SizedBox(width: AppSpace.s6),
                  trailing ??
                      ChannelBadge(
                        channelProviderNeedLabel(l10n, preset.need),
                        tone: preset.need == ChannelProviderNeed.endpoint
                            ? ChannelBadgeTone.info
                            : ChannelBadgeTone.neutral,
                        onTint: selected,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the provider list shows when a search matched nothing: the glyph, the
/// sentence, and a way out through the custom group — which is where any
/// provider the catalogue does not name gets added.
class ChannelProviderNoMatch extends StatelessWidget {
  const ChannelProviderNoMatch({
    super.key,
    required this.l10n,
    required this.onUseCustom,
    this.query = '',
  });

  final AppLocalizations l10n;
  final VoidCallback onUseCustom;

  /// What was searched for, quoted back in the explanation.
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final custom = channelFallbackCustomPreset();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 28, color: colorScheme.outline),
            const SizedBox(height: AppSpace.s10),
            Text(
              l10n.noProviderMatch,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: AppSpace.s4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                query.isEmpty
                    ? l10n.providerGroupCustomHint
                    : l10n.providerNoMatchHint(query),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            AppButton(
              label: l10n.providerUseCustom,
              icon: custom.icon,
              onPressed: onUseCustom,
            ),
          ],
        ),
      ),
    );
  }
}
