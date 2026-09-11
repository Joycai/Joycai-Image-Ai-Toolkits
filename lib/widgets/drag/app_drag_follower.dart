import 'package:flutter/material.dart';

import '../../core/app_effects.dart';
import '../../core/app_semantic_colors.dart';
import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';

/// What a drop will do, as the follower tells it (`00d · 1e`).
enum AppDragTone {
  /// The accent: a move, or any drag that is not a copy.
  move,

  /// The success colour: a copy (the copy modifier is held).
  copy,

  /// The error colour: the target under the pointer will not take this.
  reject,
}

extension on AppDragTone {
  Color color(BuildContext context) => switch (this) {
        AppDragTone.move => Theme.of(context).colorScheme.primary,
        AppDragTone.copy => context.semantic.success,
        AppDragTone.reject => Theme.of(context).colorScheme.error,
      };

  Color onColor(BuildContext context) => switch (this) {
        AppDragTone.move => Theme.of(context).colorScheme.onPrimary,
        AppDragTone.copy => context.semantic.onSuccess,
        AppDragTone.reject => Theme.of(context).colorScheme.onError,
      };
}

/// The lift shadow of `00d`: `0 12 28`, heavier on the dark theme where the
/// ground is already near black.
List<BoxShadow> appDragShadow(BuildContext context, {double t = 1}) {
  final theme = Theme.of(context);
  if (AppEffects.reduced(context)) {
    // `1g`: the follower was never glass; only its shadow steps down.
    return theme.colorScheme.shadowResting;
  }
  final alpha = theme.brightness == Brightness.dark ? 0.5 : 0.22;
  return [
    BoxShadow(
      color: theme.colorScheme.shadow.withValues(alpha: alpha * t),
      blurRadius: 28 * t,
      offset: Offset(0, 12 * t),
    ),
  ];
}

/// The chip that follows the pointer during a drag (`00d · 1e`): 30 tall at
/// r10, an opaque panel with a 1px edge in the [tone]'s colour, the glyph in
/// that colour, what is dragged or what a release does, and a count badge.
///
/// Opaque, not glass: backdrop blur smears behind something moving at pointer
/// speed and flips tone crossing light and dark content — and being opaque it
/// takes nothing from the screen's glass budget.
///
/// The top-left 12 / 12 is left empty so the pointer, anchored at the widget's
/// origin with [pointerDragAnchorStrategy], sits off the chip.
class AppDragFollower extends StatelessWidget {
  const AppDragFollower({
    super.key,
    required this.icon,
    required this.label,
    this.count,
    this.tone = AppDragTone.move,
  });

  final IconData icon;
  final String label;

  /// Shown as an 18 round badge when more than one thing is dragged.
  final int? count;

  final AppDragTone tone;

  static const double height = 30;
  static const Offset pointerOffset = Offset(12, 12);

  /// A long folder name or refusal reason ellipsizes here rather than
  /// stretching the chip across the window.
  static const double maxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color accent = tone.color(context);

    return Padding(
      padding: EdgeInsets.only(left: pointerOffset.dx, top: pointerOffset.dy),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: height,
          constraints: const BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: accent),
            boxShadow: appDragShadow(context),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSize.iconMd, color: accent),
              const SizedBox(width: AppSpace.s6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall!.metricsOnly.copyWith(
                    fontWeight: FontWeight.w500,
                    color: tone == AppDragTone.reject ? scheme.error : scheme.onSurface,
                  ),
                ),
              ),
              if (count != null && count! > 1) ...[
                const SizedBox(width: AppSpace.s6),
                AppDragCountBadge(count: count!, tone: tone),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The 18 round count of a multi-item drag, in the tone's solid colour.
class AppDragCountBadge extends StatelessWidget {
  const AppDragCountBadge({super.key, required this.count, this.tone = AppDragTone.move});

  final int count;
  final AppDragTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tone.color(context), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall!.mono.metricsOnly.copyWith(
              fontWeight: FontWeight.w600,
              color: tone.onColor(context),
            ),
      ),
    );
  }
}

/// An image card's follower (`00d · 1e` 图片卡): the thumbnail at [size]
/// (88) and r10 inside a 2px accent ring — a thumbnail takes a 2px ring, not
/// the 1px edge, which an image's own edge would swallow.
class AppImageDragFollower extends StatelessWidget {
  const AppImageDragFollower({super.key, required this.image, this.size = 88, this.count});

  final ImageProvider image;
  final double size;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.control);

    return Padding(
      padding: EdgeInsets.only(left: AppDragFollower.pointerOffset.dx, top: AppDragFollower.pointerOffset.dy),
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: radius, boxShadow: appDragShadow(context)),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: radius,
                  child: Image(image: image, fit: BoxFit.cover),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
              ),
              if (count != null && count! > 1)
                Positioned(top: AppSpace.s4, right: AppSpace.s4, child: AppDragCountBadge(count: count!)),
            ],
          ),
        ),
      ),
    );
  }
}
