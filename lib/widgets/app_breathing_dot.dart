import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// A status dot that breathes while something is running.
///
/// `00 · 1e`: the 1.6s breath is the **only** looping animation in the app.
/// It stops under the platform's reduce-motion and under the app's own
/// reduce-visual-effects ([AppMotion.breathes]); the dot stays, solid.
class AppBreathingDot extends StatefulWidget {
  const AppBreathingDot({
    super.key,
    required this.color,
    this.size = 8,
    this.breathing = true,
  });

  final Color color;
  final double size;

  /// Whether the work this dot reports is live. A dot for an idle or failed
  /// state passes false and is simply a dot.
  final bool breathing;

  @override
  State<AppBreathingDot> createState() => _AppBreathingDotState();
}

class _AppBreathingDotState extends State<AppBreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: AppMotion.breath);

  /// 1 → .35 → 1 over one period, eased at both ends like CSS `pulse`.
  ///
  /// Driven off the controller rather than recomputed in a builder: a
  /// [FadeTransition] fed this animation repaints without rebuilding, so a
  /// breath costs no element work at all.
  late final Animation<double> _opacity = _controller.drive(
    TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0.35)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.35, end: 1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ]),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AppBreathingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final shouldRun = widget.breathing && AppMotion.breathes(context);
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = DecoratedBox(
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      child: SizedBox.square(dimension: widget.size),
    );
    // The boundary is the point of this widget's whole shape. The capsule in
    // the app shell (main.dart) puts a dot *inside* a BackdropFilter, and
    // `markNeedsPaint` bubbles to the nearest repaint boundary — so without
    // one here, every breath re-recorded the glass above it, sixty times a
    // second, on whatever screen the user happened to be looking at. The two
    // dots inside the task list got a boundary for free from the ListView;
    // this one had none the whole way up.
    return RepaintBoundary(
      child: FadeTransition(opacity: _opacity, child: dot),
    );
  }
}
