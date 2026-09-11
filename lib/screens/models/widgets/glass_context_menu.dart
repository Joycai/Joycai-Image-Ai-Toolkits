import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../widgets/glass/app_glass.dart';

/// One row of a [showGlassContextMenu] menu, or a divider between groups.
@immutable
class GlassMenuItem {
  const GlassMenuItem({
    required IconData this.icon,
    required this.label,
    required this.onSelected,
    this.shortcut,
    this.danger = false,
    this.enabled = true,
  }) : isDivider = false;

  const GlassMenuItem.divider()
      : icon = null,
        label = '',
        onSelected = null,
        shortcut = null,
        danger = false,
        enabled = false,
        isDivider = true;

  final IconData? icon;
  final String label;

  /// Runs after the menu has closed, so a dialog it opens is not stacked over
  /// a route on its way out.
  final VoidCallback? onSelected;

  /// A key hint set in mono at the row's end — `Alt+↑`.
  final String? shortcut;

  /// The error ink, for the one destructive row.
  final bool danger;

  final bool enabled;
  final bool isDivider;
}

/// The menu's width (`D1a · 1b` 「右键菜单 G2 230」).
const double kGlassMenuWidth = 230;

/// Opens a glass context menu (G2 float, r16) with its top-left corner at
/// [position], flipped or clamped to stay on screen.
///
/// Its own route rather than `showMenu`: Material's popup route draws inside
/// its own clip, where a backdrop filter has nothing to sample (see the
/// popup-menu note in `app_theme.dart`). A transparent [PopupRoute] puts the
/// glass straight on the overlay, and reduce-visual-effects still turns it
/// into the opaque panel through [AppGlass].
Future<void> showGlassContextMenu(
  BuildContext context, {
  required Offset position,
  required List<GlassMenuItem> items,
  double width = kGlassMenuWidth,
}) {
  final navigator = Navigator.of(context);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push(_GlassMenuRoute(
    position: position,
    items: items,
    width: width,
    themes: themes,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  ));
}

class _GlassMenuRoute extends PopupRoute<void> {
  _GlassMenuRoute({
    required this.position,
    required this.items,
    required this.width,
    required this.themes,
    required this.barrierLabel,
  });

  final Offset position;
  final List<GlassMenuItem> items;
  final double width;
  final CapturedThemes themes;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  /// M2 in (`00 · 1e`: menus opening), M1 out.
  @override
  Duration get transitionDuration => AppMotion.state;

  @override
  Duration get reverseTransitionDuration => AppMotion.hover;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final reduced = AppMotion.prefersReduced(context);
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.quick);

    Widget menu = themes.wrap(_GlassMenu(items: items, width: width));
    if (!reduced) {
      menu = FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          alignment: Alignment.topLeft,
          child: menu,
        ),
      );
    }

    return CustomSingleChildLayout(
      delegate: _GlassMenuLayout(position: position),
      child: menu,
    );
  }
}

class _GlassMenuLayout extends SingleChildLayoutDelegate {
  _GlassMenuLayout({required this.position});

  final Offset position;

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = position.dx;
    double y = position.dy;
    // Flip to the other side of the pointer before clamping: a menu that
    // opens up and to the left of a click near the bottom-right corner still
    // has its edge at the click.
    if (x + childSize.width > size.width - _margin) x = position.dx - childSize.width;
    if (y + childSize.height > size.height - _margin) y = position.dy - childSize.height;
    x = x.clamp(_margin, math.max(_margin, size.width - _margin - childSize.width));
    y = y.clamp(_margin, math.max(_margin, size.height - _margin - childSize.height));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_GlassMenuLayout oldDelegate) => oldDelegate.position != position;
}

class _GlassMenu extends StatelessWidget {
  const _GlassMenu({required this.items, required this.width});

  final List<GlassMenuItem> items;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppGlass(
        grade: GlassGrade.float,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        padding: const EdgeInsets.all(AppSpace.s6),
        // A Material for the rows' ink and a default text style: a route page
        // has neither of its own.
        child: Material(
          type: MaterialType.transparency,
          child: FocusTraversalGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final item in items) _GlassMenuRow(item: item)],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassMenuRow extends StatelessWidget {
  const _GlassMenuRow({required this.item});

  final GlassMenuItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    if (item.isDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: AppSpace.s4),
        child: SizedBox(height: 1, child: ColoredBox(color: glass?.edge ?? scheme.outlineVariant)),
      );
    }

    final enabled = item.enabled && item.onSelected != null;
    final Color dim = ink2.withValues(alpha: ink2.a * 0.6);
    final Color labelColor = !enabled ? dim : (item.danger ? scheme.error : ink);
    final Color iconColor = !enabled ? dim : (item.danger ? scheme.error : ink2);
    final radius = BorderRadius.circular(AppRadius.sm);

    return Semantics(
      button: true,
      enabled: enabled,
      label: item.label,
      child: InkWell(
        borderRadius: radius,
        hoverColor: ink.withValues(alpha: 0.08),
        focusColor: ink.withValues(alpha: 0.08),
        highlightColor: ink.withValues(alpha: 0.12),
        splashFactory: NoSplash.splashFactory,
        onTap: enabled
            ? () {
                final callback = item.onSelected!;
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) => callback());
              }
            : null,
        child: SizedBox(
          height: AppSize.control,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
            child: Row(
              children: [
                Icon(item.icon, size: AppSize.iconMd, color: iconColor),
                const SizedBox(width: AppSpace.s10),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(color: labelColor),
                  ),
                ),
                if (item.shortcut != null) ...[
                  const SizedBox(width: AppSpace.s10),
                  Text(
                    item.shortcut!,
                    maxLines: 1,
                    style: textTheme.labelSmall?.mono.copyWith(color: dim == labelColor ? dim : ink2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
