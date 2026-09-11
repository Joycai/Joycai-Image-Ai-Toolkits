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
    return AnimatedBuilder(
      animation: _controller,
      child: dot,
      builder: (context, child) {
        // 1 → .35 → 1 over one period, eased at both ends like CSS `pulse`.
        final t = _controller.value;
        final wave = t < 0.5 ? t * 2 : (1 - t) * 2;
        final opacity = 1 - 0.65 * Curves.easeInOut.transform(wave);
        return Opacity(opacity: opacity, child: child);
      },
    );
  }
}
