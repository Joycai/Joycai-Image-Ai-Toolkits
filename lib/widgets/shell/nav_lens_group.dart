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
  /// The 36px desktop title bar: 32×28 items (`01 · 1b`).
  titleBar(itemWidth: 32, itemHeight: 28),

  /// The 48px tablet top bar: 40×36 items (`01` spec 「透镜 · 平板 36×40」).
  topBar(itemWidth: 40, itemHeight: 36);

  const NavLensDensity({required this.itemWidth, required this.itemHeight});

  final double itemWidth;
  final double itemHeight;
}

/// The eight destinations as one row of glyphs on a glass bar, the current one
/// expanded into an icon-and-label lens (`01 设计系统 · 1b` 「顶栏合一」).
///
/// Why glyphs: a Japanese label is up to twice the English one, and a row of
/// eight labels would be the first thing to break at an ordinary window width.
/// Only the current destination spends width on its name; every other one
/// names itself in a tooltip that also carries its `Ctrl+N`.
///
/// The count badge on Tasks is the accent under its own ink — not red, which
/// means a task *failed*.
class NavLensGroup extends StatelessWidget {
  const NavLensGroup({
    super.key,
    required this.density,
    this.showSelectedLabel = true,
  });

  final NavLensDensity density;

  /// The first thing dropped when the bar is too narrow.
  final bool showSelectedLabel;

  static const double _gap = 2;

  /// A 1px rule with 4px either side, between the destinations and Settings.
  static const double _dividerExtent = 9;

  static TextStyle _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.metricsOnly.copyWith(fontWeight: FontWeight.w600);

  /// The width this group will take, so a bar can decide what to drop before
  /// laying it out. Measured, never guessed from a breakpoint.
  static double widthFor(
    BuildContext context, {
    required NavLensDensity density,
    required AppDestination current,
    required bool showSelectedLabel,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final destinations = AppDestination.available;
    double width = 0;
    for (final d in destinations) {
      if (d == current && showSelectedLabel) {
        final painter = TextPainter(
          text: TextSpan(text: d.label(l10n), style: _labelStyle(context)),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        width += _lensLeading + AppSize.iconLg + _lensGap + painter.width + _lensTrailing;
      } else {
        width += density.itemWidth;
      }
    }
    width += _gap * destinations.length + _dividerExtent;
    return width.ceilToDouble();
  }

  static const double _lensLeading = 6;
  static const double _lensGap = 6;
  static const double _lensTrailing = 10;

  @override
  Widget build(BuildContext context) {
    final current = AppDestination.values[
        context.select<AppState, int>((s) => s.activeScreenIndex)];
    final queueCount = context.select<TaskQueueService, int>((q) => q.queue
        .where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.processing)
        .length);
    final edge = GlassInk.maybeOf(context)?.edge ?? Theme.of(context).colorScheme.outlineVariant;

    final children = <Widget>[];
    for (final d in AppDestination.available) {
      if (d == AppDestination.settings) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(width: 1, height: 16, child: ColoredBox(color: edge)),
        ));
      }
      children.add(_NavLens(
        destination: d,
        selected: d == current,
        showLabel: showSelectedLabel,
        badge: d.showsQueueBadge ? queueCount : 0,
        density: density,
      ));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          children[i],
        ],
      ],
    );
  }
}

class _NavLens extends StatefulWidget {
  const _NavLens({
    required this.destination,
    required this.selected,
    required this.showLabel,
    required this.badge,
    required this.density,
  });

  final AppDestination destination;
  final bool selected;
  final bool showLabel;
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
    final glassInk = GlassInk.maybeOf(context);
    final ink = glassInk?.ink ?? scheme.onSurfaceVariant;
    final d = widget.destination;
    final label = d.label(l10n);
    final radius = BorderRadius.circular(AppRadius.control);

    final icon = Icon(
      widget.selected ? d.selectedIcon : d.icon,
      size: AppSize.iconLg,
      color: widget.selected ? scheme.primary : ink,
    );

    Widget box;
    if (widget.selected) {
      final lensChild = widget.showLabel
          ? Padding(
              padding: const EdgeInsets.fromLTRB(
                  NavLensGroup._lensLeading, 0, NavLensGroup._lensTrailing, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: NavLensGroup._lensGap),
                  Text(
                    label,
                    maxLines: 1,
                    style: NavLensGroup._labelStyle(context).copyWith(color: scheme.onAccentTint),
                  ),
                ],
              ),
            )
          : SizedBox(width: widget.density.itemWidth, child: Center(child: icon));
      box = SizedBox(
        height: widget.density.itemHeight,
        child: AppGlass(
          grade: GlassGrade.lens,
          borderRadius: radius,
          reducedColor: scheme.accentTint,
          child: lensChild,
        ),
      );
    } else {
      box = AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        width: widget.density.itemWidth,
        height: widget.density.itemHeight,
        decoration: BoxDecoration(
          color: _hovering ? ink.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: radius,
        ),
        child: Center(child: icon),
      );
    }

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
      constraints: const BoxConstraints(minWidth: 14),
      height: 14,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(7),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall!.mono.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: 0,
            ),
      ),
    );
  }
}
