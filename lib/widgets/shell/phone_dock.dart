import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../app_window_frame.dart';
import '../glass/app_glass.dart';
import 'app_destinations.dart';

/// The phone's floating dock (`01 · 1g`).
///
/// A float, not a bar: it is inset 16 from the sides and 24 from the bottom,
/// so it does not spend the screen's one full-width glass layer — which leaves
/// that for each screen's own top toolbar. Five cells: four destinations and
/// "more", which opens [showPhoneMoreSheet].
class PhoneDock extends StatelessWidget {
  const PhoneDock({super.key});

  static const double height = 64;
  static const double sideInset = AppSpace.s16;
  static const double bottomInset = 24;

  /// How much of the bottom of the screen a phone screen must keep clear for
  /// the dock and the gap above it (`01 · 1g`: the capsule parks at 104).
  static double clearanceOf(BuildContext context) =>
      height + bottomInset + AppSpace.s16 + MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = AppDestination.values[
        context.select<AppState, int>((s) => s.activeScreenIndex)];
    final queueCount = context.select<TaskQueueService, int>((q) => q.queue
        .where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.processing)
        .length);
    final primary = AppDestination.dockPrimary.where(AppDestination.isAvailable).toList();
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(sideInset, 0, sideInset, bottomInset + bottom),
      child: SizedBox(
        height: height,
        child: AppGlass(
          grade: GlassGrade.float,
          borderRadius: BorderRadius.circular(AppRadius.sheet),
          padding: const EdgeInsets.all(AppSpace.s6),
          child: Row(
            children: [
              for (final d in primary)
                Expanded(
                  child: _DockCell(
                    icon: current == d ? d.selectedIcon : d.icon,
                    label: d.label(l10n),
                    selected: current == d,
                    badge: d.showsQueueBadge ? queueCount : 0,
                    onTap: () => context.read<AppState>().navigateToScreen(d.index),
                  ),
                ),
              Expanded(
                child: _DockCell(
                  icon: Icons.more_horiz,
                  label: l10n.more,
                  selected: !primary.contains(current),
                  badge: 0,
                  onTap: () => showPhoneMoreSheet(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockCell extends StatelessWidget {
  const _DockCell({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glassInk = GlassInk.maybeOf(context);
    final ink2 = glassInk?.ink2 ?? scheme.onSurfaceVariant;

    final column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: AppSize.iconLg, color: selected ? scheme.primary : ink2),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: textTheme.labelSmall!.metricsOnly.copyWith(
            color: selected ? scheme.onAccentTint : ink2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );

    Widget cell = SizedBox(
      height: 52,
      child: selected
          ? AppGlass(
              grade: GlassGrade.lens,
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              reducedColor: scheme.accentTint,
              child: column,
            )
          : column,
    );

    if (badge > 0) {
      cell = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: cell),
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: const Offset(14, 0),
                // No `alignment` on the Container: an aligned Container grows
                // to the width it is offered, and here that is the whole cell.
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16, maxHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                    '$badge',
                    style: textTheme.labelSmall!.mono.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      letterSpacing: 0,
                    ),
                  ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: cell,
      ),
    );
  }
}

/// The dock's "more" sheet: the app's identity, the destinations the dock has
/// no cell for, and — on a phone OS — why two of them are missing.
Future<void> showPhoneMoreSheet(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: scheme.scrim,
    elevation: 0,
    isScrollControlled: true,
    builder: (sheetContext) => const _MoreSheet(),
  );
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final current = AppDestination.values[
        context.select<AppState, int>((s) => s.activeScreenIndex)];
    final rest = AppDestination.available
        .where((d) => !AppDestination.dockPrimary.contains(d))
        .toList();
    final (title, version) = windowTitleParts(context);
    final isPhoneOs = Platform.isAndroid || Platform.isIOS;

    return AppGlass(
      grade: GlassGrade.float,
      edges: GlassEdges.top,
      shadow: false,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      child: Builder(builder: (context) {
        final glassInk = GlassInk.maybeOf(context);
        final ink2 = glassInk?.ink2 ?? scheme.onSurfaceVariant;
        final edge = glassInk?.edge ?? scheme.outlineVariant;
        return Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.s16, 8, AppSpace.s16, 34 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: ink2,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 14),
                child: Row(
                  children: [
                    const AppMark(size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: textTheme.titleMedium!.metricsOnly.copyWith(fontWeight: FontWeight.w600)),
                          if (version != null)
                            Text('v$version', style: textTheme.bodySmall!.mono.copyWith(color: ink2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              for (final d in rest)
                _MoreRow(
                  icon: current == d ? d.selectedIcon : d.icon,
                  label: d.label(l10n),
                  selected: current == d,
                  onTap: () {
                    Navigator.of(context).pop();
                    context.read<AppState>().navigateToScreen(d.index);
                  },
                ),
              if (isPhoneOs) ...[
                Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 6), color: edge),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l10n.moreSheetDesktopOnlyNote,
                    style: textTheme.bodySmall!.metricsOnly.copyWith(color: ink2, height: AppType.proseHeight),
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glassInk = GlassInk.maybeOf(context);
    final ink = glassInk?.ink ?? scheme.onSurface;
    final ink2 = glassInk?.ink2 ?? scheme.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(icon, size: AppSize.iconLg, color: selected ? scheme.primary : ink),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge!.metricsOnly.copyWith(
                      color: selected ? scheme.onAccentTint : ink,
                    ),
              ),
            ),
            Icon(Icons.chevron_right, size: AppSize.iconMd, color: ink2),
          ],
        ),
      ),
    );
  }
}
