import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// A channel's or provider's identity: the first letter of [label], white, on
/// an identity colour. Identity colours never follow the accent.
class ChannelIdentityAvatar extends StatelessWidget {
  const ChannelIdentityAvatar({
    super.key,
    required this.label,
    required this.color,
    this.size = 28,
    this.radius = AppRadius.sm,
  });

  final String label;
  final Color color;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final trimmed = label.trim();
    final TextStyle? slot = size >= 40
        ? textTheme.titleLarge
        : size >= 30
        ? textTheme.titleSmall
        : size >= 26
        ? textTheme.labelMedium
        : textTheme.labelSmall;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      child: trimmed.isEmpty
          ? Icon(Icons.cloud_queue, size: size * 0.55, color: Colors.white)
          : Text(
              trimmed.characters.first.toUpperCase(),
              style: slot?.metricsOnly.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
    );
  }
}

/// The 44px accent plate a dialog heading leads with (`add_link`,
/// `fact_check`).
class ChannelIconPlate extends StatelessWidget {
  const ChannelIconPlate(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: AppSize.touch,
      height: AppSize.touch,
      decoration: BoxDecoration(
        color: colorScheme.accentTint,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Icon(icon, size: 24, color: colorScheme.primary),
    );
  }
}

/// A channel dialog's heading: a 44 leading plate or avatar, the 16/600 title
/// over a quieter line, and the 32 close button.
///
/// The dialogs change what leads the heading per step (the wizard shows the
/// chosen provider's avatar once there is one), which `AppDialog`'s icon slot
/// cannot express — so this goes in as its `titleWidget`.
class ChannelDialogHeader extends StatelessWidget {
  const ChannelDialogHeader({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.monoSubtitle = false,
    this.onClose,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool monoSubtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitleSlot = monoSubtitle
        ? theme.textTheme.labelSmall?.mono
        : theme.textTheme.bodySmall;

    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleSlot?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close, size: AppSize.iconMd),
            tooltip: AppLocalizations.of(context)?.close,
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(
              width: AppSize.iconButton,
              height: AppSize.iconButton,
            ),
            style: IconButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The channel as the models screen's channel column draws it (`D1a` 渠道行,
/// 56 high): a 32 r6 identity avatar, the name, and a sub-line pairing the
/// tag on its own colour with a mono model count.
///
/// Drawn at rest, which is how a newly added channel first appears in the
/// column.
class ChannelListRowPreview extends StatelessWidget {
  const ChannelListRowPreview({
    super.key,
    required this.name,
    required this.tag,
    required this.color,
    required this.subline,
    this.namePlaceholder,
  });

  final String name;
  final String tag;
  final Color color;
  final String subline;

  /// Shown in the quiet ink while [name] is empty.
  final String? namePlaceholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final showPlaceholder = name.trim().isEmpty && namePlaceholder != null;

    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s10, 0, 8, 0),
        child: Row(
          children: [
            ChannelIdentityAvatar(
              label: tag.isNotEmpty ? tag : name,
              color: color,
              size: AppSize.control,
            ),
            const SizedBox(width: AppSpace.s10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showPlaceholder ? namePlaceholder! : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: showPlaceholder ? colorScheme.outline : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (tag.isNotEmpty) ...[
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.s6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.mono.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.s6),
                      ],
                      Text(
                        subline,
                        maxLines: 1,
                        style: textTheme.labelSmall?.mono.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
