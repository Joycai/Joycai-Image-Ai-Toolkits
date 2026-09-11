import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';
import 'app_drag_follower.dart';

/// `00d` 抬起态 as a reorderable list's `proxyDecorator`: the dragged item
/// scales to 1.02 over M2 while its `0 12 28` shadow grows in and its edge
/// turns from the hairline to a 1px accent. It never drops in opacity.
///
/// With less motion (`1g`) nothing scales or grows: the item takes a 2px accent
/// ring at once.
///
/// [slotPadding] is the part of the item that is not the card — the gap under
/// it — so the shadow and edge follow the card. With [edge] off the item
/// paints its own lifted edge (a channel row does) and only the scale and
/// shadow come from here.
Widget appReorderLiftDecorator(
  Widget child,
  int index,
  Animation<double> animation, {
  EdgeInsets slotPadding = EdgeInsets.zero,
  double radius = AppRadius.control,
  bool edge = true,
}) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final scheme = Theme.of(context).colorScheme;
      final reduced = AppMotion.prefersReduced(context);
      final t = reduced ? 1.0 : AppMotion.enter.transform(animation.value);
      final borderRadius = BorderRadius.circular(radius);

      final Widget lifted = Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            if (!reduced)
              Positioned.fill(
                child: Padding(
                  padding: slotPadding,
                  child: DecoratedBox(
                    decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: appDragShadow(context, t: t)),
                  ),
                ),
              ),
            child!,
            if (edge || reduced)
              Positioned.fill(
                child: Padding(
                  padding: slotPadding,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        border: Border.all(
                          color: reduced ? scheme.primary : Color.lerp(scheme.outlineVariant, scheme.primary, t)!,
                          width: reduced ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

      return reduced ? lifted : Transform.scale(scale: 1 + 0.02 * t, child: lifted);
    },
  );
}

/// A reorderable list's touch drag start at `00d · 1f`'s 300ms — the
/// framework waits 500ms, which reads as the app not having noticed the
/// finger.
class AppLongPressDragStartListener extends ReorderableDelayedDragStartListener {
  const AppLongPressDragStartListener({
    super.key,
    required super.index,
    required super.child,
    super.enabled,
  });

  static const Duration delay = Duration(milliseconds: 300);

  @override
  MultiDragGestureRecognizer createRecognizer() => DelayedMultiDragGestureRecognizer(delay: delay, debugOwner: this);
}
