import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../../../widgets/glass/app_glass.dart';

/// The desktop and tablet host of the size picker (`A1c · 30b` / `30h`): a
/// float-grade glass shell anchored under the field — its right edge on the
/// field's right edge, 6 below it — growing leftwards over the gallery, so the
/// image just chosen stays visible behind it. Every input sits on an opaque
/// panel inside the shell (r16 = r10 + 6); with reduced effects the shell
/// turns opaque and nothing moves.
///
/// A tap outside closes it like Enter — the picker applies as it goes, so
/// there is nothing left to commit.
Future<void> showSizePopover(
  BuildContext anchor, {
  required double width,
  required Widget Function(BuildContext context, VoidCallback close) builder,
}) {
  final navigator = Navigator.of(anchor);
  final box = anchor.findRenderObject() as RenderBox?;
  final overlayBox = navigator.overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || overlayBox == null || !overlayBox.hasSize) {
    return Future.value();
  }
  // Overlay coordinates, not window ones: the navigator's overlay starts
  // under the custom title bar.
  final topLeft = overlayBox.globalToLocal(box.localToGlobal(Offset.zero));
  final anchorRect = topLeft & box.size;
  return navigator.push<void>(
    _SizePopoverRoute(
      anchorRect: anchorRect,
      width: width,
      builder: builder,
      themes: InheritedTheme.capture(from: anchor, to: navigator.context),
      duration: AppMotion.durationOf(anchor, AppMotion.panel),
      barrierLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
    ),
  );
}

class _SizePopoverRoute extends PopupRoute<void> {
  _SizePopoverRoute({
    required this.anchorRect,
    required this.width,
    required this.builder,
    required this.themes,
    required this.duration,
    required this.barrierLabel,
  });

  final Rect anchorRect;
  final double width;
  final Widget Function(BuildContext context, VoidCallback close) builder;
  final CapturedThemes themes;
  final Duration duration;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  /// M3 in; out at `exitFactor` of it (`30i`: 280 → 168).
  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration * AppMotion.exitFactor;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    return themes.wrap(
      CustomSingleChildLayout(
        delegate: _SizePopoverLayout(anchorRect: anchorRect, width: width, padding: padding),
        child: Material(
          type: MaterialType.transparency,
          child: AppGlass(
            grade: GlassGrade.float,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            padding: const EdgeInsets.all(AppSpace.s6),
            reducedColor: scheme.surfaceContainerLow,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(11),
                child: builder(context, () => Navigator.of(context).maybePop()),
              ),
            ),
          ),
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
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.emphasized,
      reverseCurve: AppMotion.quick,
    );
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -6 * (1 - t)),
            child: Transform(
              alignment: Alignment.topRight,
              transform: Matrix4.diagonal3Values(1, 0.96 + 0.04 * t, 1),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Right edge on the field's right edge, 6 under it; above it instead when
/// the room below is too short for the panel and the room above is not.
class _SizePopoverLayout extends SingleChildLayoutDelegate {
  _SizePopoverLayout({required this.anchorRect, required this.width, required this.padding});

  final Rect anchorRect;
  final double width;
  final EdgeInsets padding;

  static const double _margin = 8;
  static const double _gap = AppSpace.s6;

  double _below(Size size) => size.height - padding.bottom - _margin - (anchorRect.bottom + _gap);
  double _above(Size size) => anchorRect.top - _gap - padding.top - _margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final size = constraints.biggest;
    final room = math.max(_below(size), _above(size));
    final w = math.min(width, size.width - padding.horizontal - _margin * 2);
    return BoxConstraints(minWidth: w, maxWidth: w, maxHeight: math.max(0, room));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = padding.left + _margin;
    final maxX = math.max(minX, size.width - padding.right - _margin - childSize.width);
    final x = (anchorRect.right - childSize.width).clamp(minX, maxX);
    final fitsBelow = childSize.height <= _below(size);
    final y = fitsBelow || _below(size) >= _above(size)
        ? anchorRect.bottom + _gap
        : anchorRect.top - _gap - childSize.height;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_SizePopoverLayout oldDelegate) =>
      oldDelegate.anchorRect != anchorRect ||
      oldDelegate.width != width ||
      oldDelegate.padding != padding;
}
