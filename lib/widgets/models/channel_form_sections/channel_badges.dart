import 'package:flutter/material.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../ui/app_switch.dart';

/// Which condition a [ChannelBadge] reports.
enum ChannelBadgeTone {
  /// A requirement or a count (`Key only`, `3 ways in`): card fill, grey ink.
  neutral,

  /// Something the next step will ask for (`Needs address`).
  info,

  /// A state worth a second look (`Deprecated`, `Address edited`).
  warning,
}

/// The r4 badge `D1b` hangs on provider rows and field labels.
class ChannelBadge extends StatelessWidget {
  const ChannelBadge(
    this.label, {
    super.key,
    this.tone = ChannelBadgeTone.neutral,
    this.mono = false,
    this.onTint = false,
  });

  final String label;
  final ChannelBadgeTone tone;
  final bool mono;

  /// On a selected row the neutral fill steps up to the panel, or it would
  /// sink into the accent wash behind it.
  final bool onTint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final semantic = context.semantic;
    final (Color background, Color foreground) = switch (tone) {
      ChannelBadgeTone.neutral => (
          onTint ? colorScheme.surface : colorScheme.surfaceContainer,
          colorScheme.onSurfaceVariant,
        ),
      ChannelBadgeTone.info => (semantic.infoContainer, semantic.onInfoContainer),
      ChannelBadgeTone.warning => (
          semantic.warningContainer,
          semantic.onWarningContainer,
        ),
    };
    final slot = theme.textTheme.labelSmall;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (mono ? slot?.mono : slot)?.copyWith(color: foreground),
      ),
    );
  }
}

/// A warning strip on the warning container — the editor's "switching preset
/// overwrites" note, the preview's empty-key note.
class ChannelNoteStrip extends StatelessWidget {
  const ChannelNoteStrip(this.text, {super.key, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s10, vertical: AppSpace.s6 + 2),
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon,
                size: AppSize.iconMd, color: semantic.onWarningContainer),
          ),
          const SizedBox(width: AppSpace.s6 + 2),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: semantic.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting that is one switch: a column-coloured card with a hairline, a
/// 600 title, an 11px description and the switch (`D1b 1d` 启用模型发现卡).
class ChannelToggleCard extends StatelessWidget {
  const ChannelToggleCard({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s10 + 2, AppSpace.s10, AppSpace.s10, AppSpace.s10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.s10),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
