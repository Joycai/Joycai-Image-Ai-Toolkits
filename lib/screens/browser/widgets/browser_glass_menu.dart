import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../widgets/glass/app_glass.dart';

/// One line of a [showBrowserGlassMenu].
abstract class BrowserMenuEntry {
  const BrowserMenuEntry();
}

/// An action row: 28 tall at r6, glyph, label and an optional mono hint on
/// the right — a keyboard shortcut or a count (`B1a · 1b`).
class BrowserMenuItem extends BrowserMenuEntry {
  const BrowserMenuItem({
    this.icon,
    required this.label,
    required this.onSelected,
    this.trailing,
    this.enabled = true,
    this.danger = false,
  });

  final IconData? icon;
  final String label;

  /// Right-aligned hint in mono at `gink2`. Only for a key the action really
  /// has, or a count the label would otherwise have to carry.
  final String? trailing;

  /// Runs after the menu has closed, so a dialog it opens does not stack
  /// under the menu's exit.
  final VoidCallback onSelected;
  final bool enabled;
  final bool danger;
}

/// A 1px rule between groups, in the glass edge colour.
class BrowserMenuDivider extends BrowserMenuEntry {
  const BrowserMenuDivider();
}

/// Opens a G2 glass context menu at the global [position] (`B1a · 1b`: 230
/// wide, r16, 6 of padding, 28px rows at r6).
///
/// A route of its own rather than [showMenu]: Material's menu route paints
/// its own opaque surface behind its clip, and a backdrop filter cannot be
/// hung under it — which is why the design-token doc lists the popup menu as
/// a degraded glass form. This one is the real float grade, and falls back
/// to the opaque panel under *reduce visual effects* through [AppGlass].
///
/// The menu flips to the left of / above the pointer when it would run off
/// the window, and is keyboard-navigable: the first enabled row takes focus,
/// arrows move, Enter activates, Esc dismisses.
Future<void> showBrowserGlassMenu({
  required BuildContext context,
  required Offset position,
  required List<BrowserMenuEntry> entries,
  double width = 230,
}) async {
  final navigator = Navigator.of(context);
  final action = await navigator.push<VoidCallback>(
    _BrowserMenuRoute(
      position: position,
      entries: entries,
      width: width,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
  action?.call();
}

class _BrowserMenuRoute extends PopupRoute<VoidCallback> {
  _BrowserMenuRoute({
    required this.position,
    required this.entries,
    required this.width,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Offset position;
  final List<BrowserMenuEntry> entries;
  final double width;
  final CapturedThemes capturedThemes;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  // M2 in, M1 out: a menu opening is a state change, and one closing should
  // get out of the way of whatever was chosen.
  @override
  Duration get transitionDuration => AppMotion.state;

  @override
  Duration get reverseTransitionDuration => AppMotion.hover;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return capturedThemes.wrap(
      Builder(
        builder: (context) => CustomSingleChildLayout(
          delegate: _MenuPositionDelegate(position: position, padding: MediaQuery.paddingOf(context)),
          child: _BrowserMenuPanel(width: width, entries: entries),
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
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.quick),
      child: child,
    );
  }
}

class _MenuPositionDelegate extends SingleChildLayoutDelegate {
  _MenuPositionDelegate({required this.position, required this.padding});

  final Offset position;
  final EdgeInsets padding;

  static const double _margin = AppSpace.s6;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(padding + const EdgeInsets.all(_margin));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = position.dx;
    double y = position.dy;
    final right = size.width - padding.right - _margin;
    final bottom = size.height - padding.bottom - _margin;
    if (x + childSize.width > right) x = position.dx - childSize.width;
    if (y + childSize.height > bottom) y = position.dy - childSize.height;
    final minX = padding.left + _margin;
    final minY = padding.top + _margin;
    x = x.clamp(minX, math.max(minX, right - childSize.width));
    y = y.clamp(minY, math.max(minY, bottom - childSize.height));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuPositionDelegate oldDelegate) =>
      oldDelegate.position != position || oldDelegate.padding != padding;
}

class _BrowserMenuPanel extends StatelessWidget {
  const _BrowserMenuPanel({required this.width, required this.entries});

  final double width;
  final List<BrowserMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final firstEnabled = entries.indexWhere((e) => e is BrowserMenuItem && e.enabled);

    return SizedBox(
      width: width,
      child: AppGlass(
        grade: GlassGrade.float,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        padding: const EdgeInsets.all(AppSpace.s6),
        child: Material(
          type: MaterialType.transparency,
          child: FocusTraversalGroup(
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int i = 0; i < entries.length; i++)
                    switch (entries[i]) {
                      final BrowserMenuItem item => _BrowserMenuRow(item: item, autofocus: i == firstEnabled),
                      _ => const _BrowserMenuRule(),
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

class _BrowserMenuRule extends StatelessWidget {
  const _BrowserMenuRule();

  @override
  Widget build(BuildContext context) {
    final edge = GlassInk.maybeOf(context)?.edge ?? Theme.of(context).colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s4, horizontal: AppSpace.s4),
      child: SizedBox(height: 1, child: ColoredBox(color: edge)),
    );
  }
}

class _BrowserMenuRow extends StatelessWidget {
  const _BrowserMenuRow({required this.item, required this.autofocus});

  final BrowserMenuItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final glass = GlassInk.maybeOf(context);
    final ink = glass?.ink ?? scheme.onSurface;
    final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
    final enabled = item.enabled;

    final Color color = !enabled
        ? ink2.withValues(alpha: ink2.a * 0.6)
        : item.danger
            ? scheme.error
            : ink;

    return InkWell(
      autofocus: autofocus && enabled,
      onTap: enabled ? () => Navigator.of(context).pop<VoidCallback>(item.onSelected) : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      hoverColor: ink.withValues(alpha: 0.08),
      focusColor: ink.withValues(alpha: 0.10),
      highlightColor: ink.withValues(alpha: 0.12),
      splashFactory: NoSplash.splashFactory,
      child: SizedBox(
        height: AppSize.compact,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: AppSize.iconMd, color: color),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall!.metricsOnly.copyWith(color: color),
                ),
              ),
              if (item.trailing != null) ...[
                const SizedBox(width: 10),
                Text(
                  item.trailing!,
                  maxLines: 1,
                  style: textTheme.labelSmall!.mono.metricsOnly.copyWith(
                    color: ink2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
