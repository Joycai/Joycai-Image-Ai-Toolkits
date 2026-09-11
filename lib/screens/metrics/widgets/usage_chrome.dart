import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_dialog.dart';
import 'usage_controller.dart';

/// `D2`'s card: the panel ground, a hairline, r16.
///
/// Opaque on purpose. This screen is all numbers and spends no glass beyond
/// the shell's own bar, so its cards stand on the aurora as plain panels.
class UsagePanel extends StatelessWidget {
  const UsagePanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Material, not a decorated box: rows and buttons inside draw their ink on
    // the nearest Material, and the records table clips to these corners.
    return Material(
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

/// The 11/500 tracked caption in the deep ink that heads a card.
///
/// Not upper-cased, unlike `AppSectionLabel`: these name what the numbers
/// under them total, and are matched by that name.
class UsageCaption extends StatelessWidget {
  const UsageCaption(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: AppType.trackedLabelSpacing,
            color: Theme.of(context).colorScheme.onAccentTint,
          ),
    );
  }
}

/// The dot that keys a figure to its identity colour.
class UsageDot extends StatelessWidget {
  const UsageDot(this.color, {super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

/// A thin share bar: the track, and [share] of it in [color].
class UsageShareBar extends StatelessWidget {
  const UsageShareBar({super.key, required this.share, required this.color, this.height = 4});

  final double share;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: share.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card that stands in for the groups and records while a range loads:
/// the accent ring on its track, and a line saying what it is waiting for.
class UsageLoadingCard extends StatelessWidget {
  const UsageLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return UsagePanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: AppSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpace.s10),
            Text(
              AppLocalizations.of(context)!.usageLoadingRecords,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 32px square action on the canvas: the panel ground with a hairline, or
/// with [danger] the error ink inside a 50% error edge.
class UsageToolIconButton extends StatelessWidget {
  const UsageToolIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: Icon(icon, size: AppSize.iconMd),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: AppSize.iconButton,
        height: AppSize.iconButton,
      ),
      style: IconButton.styleFrom(
        backgroundColor: danger ? null : colorScheme.surface,
        foregroundColor: danger ? colorScheme.error : colorScheme.onSurface,
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: AppAlpha.disabled),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(
            color: danger
                ? colorScheme.error.withValues(alpha: AppAlpha.edge)
                : colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

/// Asks before deleting every usage record, then clears and reloads
/// [controller].
Future<void> showClearAllUsageDialog(BuildContext context, UsageController controller) {
  final l10n = AppLocalizations.of(context)!;
  final colorScheme = Theme.of(context).colorScheme;
  final total = controller.totalRecords;

  return AppDialog.show<void>(
    context,
    icon: Icons.delete_sweep_outlined,
    iconColor: colorScheme.error,
    title: l10n.clearAllUsage,
    subtitle: total == null ? null : l10n.usageRecordCount(total),
    maxWidth: 460,
    content: Text(l10n.clearUsageWarning),
    actions: [
      AppButton(
        label: l10n.cancel,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
      AppButton(
        label: l10n.clearAll,
        variant: AppButtonVariant.destructive,
        onPressed: () async {
          await controller.clearTokenUsage();
          if (context.mounted) {
            Navigator.pop(context);
            controller.load(reset: true);
          }
        },
      ),
    ],
  );
}
