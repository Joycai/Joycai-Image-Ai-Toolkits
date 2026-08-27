import 'package:flutter/widgets.dart';

import '../core/design_tokens.dart';

/// The task queue's own tick.
///
/// [TaskQueueService] recomputes every running task's progress on a periodic
/// timer, and this is that timer's period — see
/// `lib/services/task_queue_service.dart`. Tweening over exactly one tick lands
/// the bar on each reported value just as the next one arrives: continuous
/// travel, with nothing to catch up on and nothing to overshoot.
///
/// Deliberately not an [AppMotion] token. That ladder is a budget for UI
/// transitions and tops out at 300ms; this is not a transition but the cadence
/// of the data being tracked, and putting it on the ladder would invite the
/// next call site to reach for it as a duration.
const Duration kTaskProgressTick = Duration(milliseconds: 500);

/// Advances a progress indicator continuously between the values the task
/// queue reports twice a second.
///
/// Flutter's progress indicators paint a determinate `value` as given — they
/// carry no implicit animation — so a bar fed straight from the queue moves
/// twice a second in visible steps. That cadence is the worst of both: too
/// slow to read as continuous, too fast to read as deliberate segmentation.
///
/// A null [value] passes straight through: an indeterminate indicator has no
/// target to interpolate towards, and Flutter's own looping animation is
/// already the right answer there.
class SmoothProgress extends StatelessWidget {
  const SmoothProgress({super.key, required this.value, required this.builder});

  /// The reported progress, or null for indeterminate.
  final double? value;

  /// Builds the indicator. The value handed back is the interpolated one, and
  /// is what the indicator's own `value:` should be given.
  final Widget Function(BuildContext context, double? value) builder;

  @override
  Widget build(BuildContext context) {
    final target = value;
    if (target == null) return builder(context, null);

    return TweenAnimationBuilder<double>(
      // No `begin`: TweenAnimationBuilder copies `end` into it on the first
      // build, so a bar that appears at 60% appears at 60% rather than
      // sweeping up from zero. Every later change retargets from wherever the
      // tween currently sits, which is what keeps a cancelled, restarted or
      // early-finishing task from jumping.
      tween: Tween<double>(end: target),
      duration: AppMotion.durationOf(context, kTaskProgressTick),
      // Constant motion, so linear. An eased progress bar speeds up and slows
      // down between two values that were themselves linear in time.
      curve: Curves.linear,
      builder: (context, v, _) => builder(context, v),
    );
  }
}
