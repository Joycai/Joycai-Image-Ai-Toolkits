import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import 'app_glass.dart';

/// One line of an [AppGlassMenu]: an [AppGlassMenuItem] or an
/// [AppGlassMenuDivider].
abstract class AppGlassMenuEntry {
  const AppGlassMenuEntry();
}

/// An action row (`00` / `B1a · 1b` 右键菜单): 28 tall at r6 — glyph, label,
/// an optional mono hint at the end, and under a disabled row an optional
/// second line saying why.
class AppGlassMenuItem extends AppGlassMenuEntry {
  const AppGlassMenuItem({
    this.icon,
    required this.label,
    required this.onSelected,
    this.trailing,
    this.note,
    this.enabled = true,
    this.danger = false,
  });

  final IconData? icon;
  final String label;

  /// Runs once the menu has been popped, so a dialog it opens is not stacked
  /// over a route on its way out. Null disables the row.
  final VoidCallback? onSelected;

  /// A key the action really has (`F2`, `Alt+↑`) or a count the label would
  /// otherwise carry, in mono at the glass's secondary ink.
  final String? trailing;

  /// Why the row is disabled — shown only while it is (`B1b · 1d`: 「根目录
  /// 不可移动」 under Move to…).
  final String? note;

  final bool enabled;

  /// The error ink, for the destructive row.
  final bool danger;

  bool get isEnabled => enabled && onSelected != null;
}

/// The rule between two groups of rows.
class AppGlassMenuDivider extends AppGlassMenuEntry {
  const AppGlassMenuDivider();
}

/// The width most menus take (`B1a`, `D1a`: 「右键菜单 G2 230」).
const double kAppGlassMenuWidth = 230;

/// Opens a float-grade glass menu with its top-left corner at the global
/// [position], flipped to the other side of the point and then clamped where
/// the window runs out.
///
/// Its own route rather than [showMenu]: Material's popup route paints its
/// panel behind its own clip, where a backdrop filter has nothing of the page
/// to sample — which is why the theme's `popupMenuTheme` is the opaque reduced
/// form. This route lays an [AppGlass] straight onto the overlay, and reduce
/// visual effects still turns it into the opaque panel through [AppGlass].
///
/// The first enabled row takes focus; arrows move, Enter activates, Esc and a
/// tap outside dismiss.
Future<void> showAppGlassMenu(
  BuildContext context, {
  required Offset position,
  required List<AppGlassMenuEntry> entries,
  double width = kAppGlassMenuWidth,
}) async {
  final navigator = Navigator.of(context);
  final action = await navigator.push<VoidCallback>(
    _AppGlassMenuRoute(
      position: position,
      entries: entries,
      width: width,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      duration: AppMotion.durationOf(context, AppMotion.state),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
  action?.call();
}

/// Where a menu dropping from a button at [anchor] should open: its right edge
/// on the button's right edge, 4px below it.
Offset appGlassMenuPositionBelow(BuildContext anchor, {double width = kAppGlassMenuWidth}) {
  final box = anchor.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Offset.zero;
  return box.localToGlobal(Offset(box.size.width - width, box.size.height + AppSpace.s4));
}

class _AppGlassMenuRoute extends PopupRoute<VoidCallback> {
  _AppGlassMenuRoute({
    required this.position,
    required this.entries,
    required this.width,
    required this.themes,
    required this.duration,
    required this.barrierLabel,
  });

  final Offset position;
  final List<AppGlassMenuEntry> entries;
  final double width;
  final CapturedThemes themes;
  final Duration duration;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  /// M2 in (`00 · 1e`: a menu opening is a state change), M1 out.
  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration == Duration.zero ? Duration.zero : AppMotion.hover;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return themes.wrap(
      Builder(
        builder: (context) => CustomSingleChildLayout(
          delegate: _AppGlassMenuLayout(position: position, padding: MediaQuery.paddingOf(context)),
          child: AppGlassMenu(width: width, entries: entries),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AppMotion.prefersReduced(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.quick);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

class _AppGlassMenuLayout extends SingleChildLayoutDelegate {
  _AppGlassMenuLayout({required this.position, required this.padding});

  final Offset position;
  final EdgeInsets padding;

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(padding + const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double minX = padding.left + _margin;
    final double minY = padding.top + _margin;
    final double maxX = math.max(minX, size.width - padding.right - _margin - childSize.width);
    final double maxY = math.max(minY, size.height - padding.bottom - _margin - childSize.height);

    // Flip to the other side of the point before clamping: a menu opened near
    // the bottom-right corner still has its corner at the click.
    double x = position.dx;
    double y = position.dy;
    if (x > maxX) x = position.dx - childSize.width;
    if (y > maxY) y = position.dy - childSize.height;
    return Offset(x.clamp(minX, maxX), y.clamp(minY, maxY));
  }

  @override
  bool shouldRelayout(_AppGlassMenuLayout oldDelegate) =>
      oldDelegate.position != position || oldDelegate.padding != padding;
}

/// The menu panel itself: G2 glass at r16 with 6 of padding around the rows.
///
/// Public so tests can find a menu's rows through it; open one with
/// [showAppGlassMenu].
class AppGlassMenu extends StatelessWidget {
  const AppGlassMenu({super.key, required this.entries, this.width = kAppGlassMenuWidth});

  final List<AppGlassMenuEntry> entries;
  final double width;

  @override
  Widget build(BuildContext context) {
    final firstEnabled = entries.indexWhere((e) => e is AppGlassMenuItem && e.isEnabled);

    return SizedBox(
      width: width,
      child: AppGlass(
        grade: GlassGrade.float,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        // A transparent Material for the rows' ink and a default text style:
        // a route page has neither of its own.
        child: Material(
          type: MaterialType.transparency,
          child: FocusTraversalGroup(
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.all(AppSpace.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < entries.length; i++)
                    switch (entries[i]) {
                      final AppGlassMenuItem item => _AppGlassMenuRow(item: item, autofocus: i == firstEnabled),
                      _ => const _AppGlassMenuRule(),
                    },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppGlassMenuRule extends StatelessWidget {
  const _AppGlassMenuRule();

  @override
  Widget build(BuildContext context) {
    final glass = GlassInk.maybeOf(context);
    // The glass's secondary ink at a hairline's weight: the glass edge colour
    // is a white refraction line and disappears on light glass, which is what
    // a menu mostly sits on. The opaque reduced form keeps the plain hairline.
    final Color color = glass == null || glass.reduced
        ? (glass?.edge ?? Theme.of(context).colorScheme.outlineVariant)
        : glass.ink2.withValues(alpha: 0.2);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: AppSpace.s4),
      child: SizedBox(height: 1, child: ColoredBox(color: color)),
    );
  }
}

class _AppGlassMenuRow extends StatelessWidget {
  const _AppGlassMenuRow({required this.item, required this.autofocus});

  final AppGlassMenuItem item;
  final bool autofocus;

  static const double _noteHeight = 42;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;

    final enabled = item.isEnabled;
    final Color dim = ink2.withValues(alpha: ink2.a * 0.6);
    final Color labelColor = !enabled ? dim : (item.danger ? scheme.error : ink);
    final Color glyphColor = !enabled ? dim : (item.danger ? scheme.error : ink2);
    final note = !enabled ? item.note : null;
    final radius = BorderRadius.circular(AppRadius.sm);

    return Semantics(
      button: true,
      enabled: enabled,
      child: InkWell(
        autofocus: autofocus,
        borderRadius: radius,
        hoverColor: ink.withValues(alpha: 0.08),
        focusColor: ink.withValues(alpha: 0.10),
        highlightColor: ink.withValues(alpha: 0.12),
        splashFactory: NoSplash.splashFactory,
        onTap: enabled ? () => Navigator.of(context).pop<VoidCallback>(item.onSelected) : null,
        child: SizedBox(
          height: note == null ? AppSize.compact : _noteHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: AppSize.iconMd, color: glyphColor),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall!.metricsOnly.copyWith(color: labelColor),
                      ),
                      if (note != null)
                        Text(
                          note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall!.metricsOnly.copyWith(
                            fontWeight: FontWeight.w400,
                            color: dim,
                          ),
                        ),
                    ],
                  ),
                ),
                if (item.trailing != null) ...[
                  const SizedBox(width: AppSpace.s10),
                  Text(
                    item.trailing!,
                    maxLines: 1,
                    style: textTheme.labelSmall!.mono.metricsOnly.copyWith(
                      fontWeight: FontWeight.w400,
                      color: enabled ? ink2 : dim,
                    ),
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
