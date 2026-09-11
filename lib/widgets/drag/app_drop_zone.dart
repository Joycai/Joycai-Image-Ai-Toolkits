import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/design_tokens.dart';
import '../dashed_border.dart';

/// The ladder of a slot or zone that takes a drop (`00d · 1c` 投放进容器).
enum AppDropZoneState {
  /// Nothing in flight: `--col` and a 1px dashed hairline.
  rest,

  /// A drag this zone accepts is in flight elsewhere on screen: the edge
  /// turns accent, the ground stays.
  armed,

  /// The pointer is over it and a release lands: 2px dashed accent on
  /// `--tint`, 「松手放入」.
  hover,

  /// The pointer is over it with something it will not take: 2px dashed
  /// error on the error container, and the reason.
  reject,

  /// It would take this, but has no room left: 2px dashed warning on the
  /// warning container, and the limit.
  full,
}

extension AppDropZoneStateColors on AppDropZoneState {
  /// The edge colour, also the zone's icon colour.
  Color edge(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (this) {
      AppDropZoneState.rest => scheme.outlineVariant,
      AppDropZoneState.armed || AppDropZoneState.hover => scheme.primary,
      AppDropZoneState.reject => scheme.error,
      AppDropZoneState.full => context.semantic.warning,
    };
  }

  /// Text on the zone's ground.
  Color ink(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (this) {
      AppDropZoneState.rest || AppDropZoneState.armed => scheme.onSurfaceVariant,
      AppDropZoneState.hover => scheme.onAccentTint,
      AppDropZoneState.reject => scheme.onErrorContainer,
      AppDropZoneState.full => context.semantic.onWarningContainer,
    };
  }

  /// The dashed edge's weight: 1px at rest and armed, 2px once the pointer is
  /// over the zone.
  double get edgeWidth => this == AppDropZoneState.rest || this == AppDropZoneState.armed ? 1 : 2;
}

/// A drop slot's ground and dashed edge for [state] (`00d · 1c`).
///
/// With [ground] off only the edge is drawn — for a slot already holding an
/// image, where the design never lays `--tint` over a picture.
class AppDropZoneFrame extends StatelessWidget {
  const AppDropZoneFrame({
    super.key,
    required this.state,
    this.child,
    this.radius = AppRadius.control,
    this.ground = true,
  });

  final AppDropZoneState state;
  final Widget? child;
  final double radius;
  final bool ground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color fill = !ground
        ? Colors.transparent
        : switch (state) {
            AppDropZoneState.rest || AppDropZoneState.armed => scheme.surfaceContainerLow,
            AppDropZoneState.hover => Color.alphaBlend(scheme.accentTint, scheme.surfaceContainerLow),
            AppDropZoneState.reject => scheme.errorContainer,
            AppDropZoneState.full => context.semantic.warningContainer,
          };

    return AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.hover),
      curve: AppMotion.quick,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(radius)),
      child: CustomPaint(
        foregroundPainter: _DashedEdgePainter(
          color: state.edge(context),
          width: state.edgeWidth,
          radius: radius,
        ),
        child: child,
      ),
    );
  }
}

class _DashedEdgePainter extends CustomPainter {
  const _DashedEdgePainter({required this.color, required this.width, required this.radius});

  final Color color;
  final double width;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(width / 2);
    drawDashedRRect(
      canvas,
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_DashedEdgePainter old) => old.color != color || old.width != width || old.radius != radius;
}

/// `00d · 1c` 整面投放: a whole surface taking files from the operating system.
///
/// `--scrim` rather than glass — a full-screen blur is too expensive — with
/// the accent wash, a 2px dashed edge inset from the surface's own, and the
/// title in the light ink the scrim is tuned for. [reject] swaps the edge to
/// the error colour and drops the wash.
class AppDropSurfaceOverlay extends StatelessWidget {
  const AppDropSurfaceOverlay({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.add_photo_alternate_outlined,
    this.reject = false,
    this.inset = const EdgeInsets.all(AppSpace.s10),
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool reject;

  /// Where the dashed edge sits inside the surface — past floating chrome.
  final EdgeInsets inset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Color edge = reject ? scheme.error : scheme.primary;

    return ColoredBox(
      color: scheme.scrim,
      child: ColoredBox(
        color: reject ? Colors.transparent : scheme.accentTint,
        child: Padding(
          padding: inset,
          child: CustomPaint(
            foregroundPainter: _DashedEdgePainter(color: edge, width: 2, radius: AppRadius.lg),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 28, color: AppOverlay.onInk),
                    const SizedBox(height: AppSpace.s10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall!.copyWith(color: AppOverlay.onInk, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpace.s4),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall!.copyWith(color: AppOverlay.onInk),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `00d` 确认: a ring laid over [child] when [trigger] changes to a new
/// non-null value — held 600ms, then faded over M1; with less motion, held
/// 1.2s and gone without a fade.
///
/// [color] defaults to the success colour (a drop into a container or onto a
/// folder); a reorder confirms with `--ring` through `AppReorderGap` instead.
class AppDropConfirmRing extends StatefulWidget {
  const AppDropConfirmRing({
    super.key,
    required this.trigger,
    required this.child,
    this.color,
    this.width = 2,
    this.radius = AppRadius.control,
  });

  final Object? trigger;
  final Widget child;
  final Color? color;
  final double width;
  final double radius;

  @override
  State<AppDropConfirmRing> createState() => _AppDropConfirmRingState();
}

class _AppDropConfirmRingState extends State<AppDropConfirmRing> with SingleTickerProviderStateMixin {
  static const Duration _hold = Duration(milliseconds: 600);
  static const Duration _reducedHold = Duration(milliseconds: 1200);

  late final AnimationController _controller = AnimationController(vsync: this);
  bool _reduced = false;

  @override
  void didUpdateWidget(AppDropConfirmRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != null && widget.trigger != oldWidget.trigger) {
      _reduced = AppMotion.prefersReduced(context);
      _controller.duration = _reduced ? _reducedHold : _hold + AppMotion.hover;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _opacity {
    if (!_controller.isAnimating) return 0;
    if (_reduced) return 1;
    final total = (_hold + AppMotion.hover).inMicroseconds;
    final t = _controller.value * total;
    if (t <= _hold.inMicroseconds) return 1;
    return 1 - AppMotion.quick.transform((t - _hold.inMicroseconds) / AppMotion.hover.inMicroseconds);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.semantic.success;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final opacity = _opacity;
                if (opacity <= 0) return const SizedBox.shrink();
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(color: color.withValues(alpha: color.a * opacity), width: widget.width),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The one-line note a drop leaves behind (`00d · 1c` 「已加入参考图 · 3 / 3」):
/// the success container at r10 with a check — not a toast, and it takes no
/// focus.
class AppDropNote extends StatelessWidget {
  const AppDropNote(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: semantic.successContainer,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: AppSize.iconSm, color: semantic.success),
            const SizedBox(width: AppSpace.s6),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall!.copyWith(
                  fontWeight: FontWeight.w400,
                  color: semantic.onSuccessContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
