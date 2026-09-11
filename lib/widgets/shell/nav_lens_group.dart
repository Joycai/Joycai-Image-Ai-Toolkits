import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../glass/app_glass.dart';
import 'app_destinations.dart';

/// Item geometry for the two bars the lens group sits in.
enum NavLensDensity {
  /// The 36px desktop title bar: 32×28 cells at r10 (`01b · 1b`).
  titleBar(itemWidth: 32, itemHeight: 28, radius: AppRadius.control),

  /// The 48px tablet top bar: 36×40 cells at r12 (`01b · 1e`).
  topBar(itemWidth: 36, itemHeight: 40, radius: 12);

  const NavLensDensity({required this.itemWidth, required this.itemHeight, required this.radius});

  final double itemWidth;
  final double itemHeight;
  final double radius;
}

/// The eight destinations as a row of equal glyph cells on a glass bar, with a
/// lens under the current one that slides from cell to cell (`01b · 1b`).
///
/// Every cell is the same width whichever destination is current. The group is
/// centred, and while the current destination spelled out its label inside the
/// group, the group's width followed that label: each switch between screens
/// with names of different lengths moved all eight icons sideways. The current
/// destination's name lives in the title instead, and every cell names itself
/// in a tooltip that also carries its `Ctrl+N`.
///
/// Only the lens moves (180ms). The icons and the screen underneath change at
/// once.
///
/// The count badge on Tasks is the accent under its own ink — not red, which
/// means a task *failed*.
class NavLensGroup extends StatelessWidget {
  const NavLensGroup({super.key, required this.density});

  final NavLensDensity density;

  static const double _gap = 2;

  /// A 1px rule with 4px either side, between the destinations and Settings.
  static const double _dividerExtent = 9;

  /// The width this group takes. It does not depend on the current
  /// destination, which is the whole point.
  static double widthFor({required NavLensDensity density}) {
    final count = AppDestination.available.length;
    // The cells, the divider, and a gap between each neighbouring pair —
    // the divider counts as a neighbour.
    return count * density.itemWidth + _dividerExtent + _gap * count;
  }

  /// Where the [index]th available destination's cell starts.
  static double _cellLeft(int index, int dividerBefore, NavLensDensity density) =>
      index * (density.itemWidth + _gap) + (index >= dividerBefore ? _dividerExtent + _gap : 0);

  @override
  Widget build(BuildContext context) {
    final current = AppDestination.values[
        context.select<AppState, int>((s) => s.activeScreenIndex)];
    final queueCount = context.select<TaskQueueService, int>((q) => q.queue
        .where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.processing)
        .length);
    final scheme = Theme.of(context).colorScheme;
    final edge = GlassInk.maybeOf(context)?.edge ?? scheme.outlineVariant;

    final destinations = AppDestination.available;
    final settingsAt = destinations.indexOf(AppDestination.settings);
    final dividerBefore = settingsAt < 0 ? destinations.length : settingsAt;
    final selected = destinations.indexOf(current);

    final cells = <Widget>[];
    for (int i = 0; i < destinations.length; i++) {
      if (i == settingsAt) {
        cells.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(width: 1, height: 16, child: ColoredBox(color: edge)),
        ));
      }
      final d = destinations[i];
      cells.add(_NavLens(
        destination: d,
        selected: d == current,
        badge: d.showsQueueBadge ? queueCount : 0,
        density: density,
      ));
    }

    return SizedBox(
      width: widthFor(density: density),
      height: density.itemHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (selected >= 0)
            AnimatedPositioned(
              duration: AppMotion.durationOf(context, AppMotion.state),
              curve: AppMotion.emphasized,
              left: _cellLeft(selected, dividerBefore, density),
              top: 0,
              width: density.itemWidth,
              height: density.itemHeight,
              child: IgnorePointer(
                child: AppGlass(
                  grade: GlassGrade.lens,
                  borderRadius: BorderRadius.circular(density.radius),
                  reducedColor: scheme.accentTint,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                cells[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _NavLens extends StatefulWidget {
  const _NavLens({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.density,
  });

  final AppDestination destination;
  final bool selected;
  final int badge;
  final NavLensDensity density;

  @override
  State<_NavLens> createState() => _NavLensState();
}

class _NavLensState extends State<_NavLens> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final ink2 = GlassInk.maybeOf(context)?.ink2 ?? scheme.onSurfaceVariant;
    final d = widget.destination;
    final label = d.label(l10n);

    Widget box = AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      width: widget.density.itemWidth,
      height: widget.density.itemHeight,
      decoration: BoxDecoration(
        // The current cell's ground is the lens sliding behind the row.
        color: _hovering && !widget.selected ? ink2.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(widget.density.radius),
      ),
      child: Center(
        child: Icon(
          widget.selected ? d.selectedIcon : d.icon,
          size: AppSize.iconLg,
          color: widget.selected ? scheme.primary : ink2,
        ),
      ),
    );

    if (widget.badge > 0) {
      box = Stack(
        clipBehavior: Clip.none,
        children: [
          box,
          Positioned(top: 1, right: 1, child: _NavBadge(count: widget.badge)),
        ],
      );
    }

    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: label,
      child: Tooltip(
        message: isDesktop ? '$label · ${d.shortcutHint}' : label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.read<AppState>().navigateToScreen(d.index),
            child: box,
          ),
        ),
      ),
    );
  }
}

/// `01 · 1b`: 14px tall, the accent under its ink, mono 11/600.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 14, minHeight: 14, maxHeight: 14),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0,
            ),
        ),
      ),
    );
  }
}
