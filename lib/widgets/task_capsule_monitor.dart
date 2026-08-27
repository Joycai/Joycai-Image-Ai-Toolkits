import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/app_theme.dart';
import '../core/responsive.dart';
import '../core/task_type_glyph.dart';
import '../l10n/app_localizations.dart';
import '../services/task_queue_service.dart';
import '../state/app_state.dart';
import 'app_button.dart';
import 'smooth_progress.dart';

class TaskCapsuleMonitor extends StatefulWidget {
  const TaskCapsuleMonitor({super.key});

  @override
  State<TaskCapsuleMonitor> createState() => _TaskCapsuleMonitorState();
}

class _TaskCapsuleMonitorState extends State<TaskCapsuleMonitor> {
  bool _isExpanded = false;
  Offset? _offset;

  /// Drag bookkeeping, allowed [_kDragSlack] past the screen bounds so the
  /// capsule re-engages where the pointer actually is after being pushed into
  /// an edge — clamping the accumulator itself detached it from the cursor
  /// for the rest of the drag. Null when no drag is live.
  static const double _kDragSlack = 24;
  Offset? _dragOffset;
  bool _dragging = false;
  bool _pressed = false;

  /// Clearance kept between the capsule and the window edge.
  static const double _kEdgeInset = 16;

  /// Where a flick would come to rest under scroll-style deceleration —
  /// the momentum-projection form (v/1000)·d/(1−d), d = 0.998.
  static double _project(double velocity) => velocity / 1000 * 0.998 / (1 - 0.998);

  /// Where the capsule parks, as (distance from the left, distance from the
  /// **bottom**).
  ///
  /// Anchored by its bottom edge rather than its top, which is what makes
  /// opening it safe. It opens by growing, it parks near the bottom, and a
  /// top-anchored capsule therefore grew its task rows and its 查看全部
  /// straight off the window — the half of the component that is worth opening
  /// at all. Grown from the bottom edge it moves *up* into the space that is
  /// actually there, and nothing has to measure how tall it became.
  ///
  /// It also sidesteps a coordinate trap: this widget's Stack sits under the
  /// custom title bar, so `MediaQuery.sizeOf` is taller than the box the
  /// capsule is actually positioned in, and any arithmetic against the bottom
  /// edge computed from it is wrong by the height of the chrome.
  void _initPosition(Size screenSize, bool isMobile) {
    if (_offset != null) return;
    // Bottom centre on mobile (clear of the navigation bar), bottom right on
    // desktop.
    _offset = isMobile ? const Offset(16, 160) : Offset(screenSize.width - 320, 100);
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);
    final screenSize = MediaQuery.sizeOf(context);

    _initPosition(screenSize, isMobile);

    // Both counts off the same list. The header used to read
    // `queue.runningCount` — a counter the service moves as it starts and
    // finishes work — while the rows below it were filtered from the task
    // statuses. The two agree in normal operation and there is no reason for
    // the capsule to depend on that: a header saying "0 running" over a list
    // of two running tasks is the one thing a monitor must never do.
    final pendingCount = queue.queue.where((t) => t.status == TaskStatus.pending).length;
    final activeTasks = queue.queue.where((t) => t.status == TaskStatus.processing).toList();
    final runningCount = activeTasks.length;

    // Resident, never unmounted: a floating, shadowed surface blinking into
    // and out of existence was the one overlay in the app that neither slid
    // nor faded. Both visibility triggers — the queue emptying and being on
    // the workbench (which has its own console) — now fade the same way.
    // Off wherever the queue is already on screen. `C1` settles the overlap
    // outright — "底部执行日志控制台与右下角浮层胶囊二选一，这一屏取控制台" — and
    // the workbench had the same argument first: a floating summary of the
    // queue parked on top of the queue itself is one report too many, and on
    // the tasks screen it landed squarely over the run console.
    final int screen = context.select<AppState, int>((s) => s.activeScreenIndex);
    final bool queueIsOnScreen = screen == 0 || screen == 2;
    final visible = (pendingCount > 0 || runningCount > 0) && !queueIsOnScreen;

    double avgProgress = 0;
    if (activeTasks.isNotEmpty) {
      double total = 0;
      int count = 0;
      for (var t in activeTasks) {
        if (t.progress != null) {
          total += t.progress!;
          count++;
        }
      }
      if (count > 0) avgProgress = total / count;
    }

    final capsuleWidth = isMobile ? (screenSize.width - 32) : (_isExpanded ? 300.0 : 196.0);

    final maxX = screenSize.width - capsuleWidth;
    // How far up from the bottom it may be dragged. Generous rather than
    // exact: the capsule's own box is what has to stay on screen, and the
    // bottom anchor already guarantees that for everything below this point.
    final maxY = screenSize.height - 80;

    // AnimatedPositioned with a zero duration while the pointer is down: the
    // drag tracks 1:1, and the same node then glides the release — the flick
    // settle and any future repositioning ride one mechanism.
    return AnimatedPositioned(
      duration: _dragging
          ? Duration.zero
          : AppMotion.durationOf(context, AppMotion.panel),
      curve: AppMotion.enter,
      left: _offset!.dx,
      bottom: _offset!.dy,
      child: IgnorePointer(
        ignoring: !visible,
        child: Listener(
          // Raw pointer events: with the pan recognizer in the arena, onTapDown
          // waits out the press timeout, and a floating control should take
          // the press the moment the pointer lands.
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
        onPanStart: (_) => setState(() {
          _dragging = true;
          _dragOffset = _offset;
        }),
        onPanUpdate: (details) {
          setState(() {
            // dy is a distance from the *bottom*, so a pointer moving down
            // makes it smaller.
            final raw = Offset(
              _dragOffset!.dx + details.delta.dx,
              _dragOffset!.dy - details.delta.dy,
            );
            _dragOffset = Offset(
              raw.dx.clamp(0.0 - _kDragSlack, maxX + _kDragSlack),
              raw.dy.clamp(0.0 - _kDragSlack, maxY + _kDragSlack),
            );
            _offset = Offset(
              _dragOffset!.dx.clamp(0.0, maxX),
              _dragOffset!.dy.clamp(0.0, maxY),
            );
          });
        },
        onPanEnd: (details) {
          // The canonical velocity-handoff case: project where the throw was
          // going, park on the nearer horizontal edge of that point, and let
          // AnimatedPositioned carry it there. A release with no velocity
          // projects to where it already is and simply stays.
          final v = details.velocity.pixelsPerSecond;
          final projected = Offset(
            _offset!.dx + _project(v.dx),
            // Same sign flip as the drag: a downward throw lands *closer* to
            // the bottom edge.
            _offset!.dy - _project(v.dy),
          );
          setState(() {
            _dragging = false;
            _dragOffset = null;
            final snapX = (projected.dx + capsuleWidth / 2) < screenSize.width / 2
                ? _kEdgeInset
                : maxX - _kEdgeInset;
            _offset = Offset(
              v.distance < 100 ? _offset!.dx : snapX,
              projected.dy.clamp(_kEdgeInset, maxY),
            );
          });
        },
        onPanCancel: () => setState(() {
          _dragging = false;
          _dragOffset = null;
        }),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: AppMotion.durationOf(context, AppMotion.reveal),
          curve: AppMotion.enter,
          child: AnimatedScale(
            scale: !visible ? 0.9 : (_pressed ? 0.97 : 1.0),
            duration: AppMotion.durationOf(
                context, visible && !_pressed ? AppMotion.reveal : AppMotion.hover),
            curve: AppMotion.enter,
            child: Material( // Fixes yellow underline
          type: MaterialType.transparency,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.reveal),
            curve: AppMotion.move,
            width: capsuleWidth,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              // `12g` floats this at 92% of a near-white, not 70% of a mid
              // grey. It sits over whatever screen is behind it — a gallery, a
              // task list — so it has to read as something laid on top; a grey
              // at 70% reads as a smudge on the content instead.
              color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
              // dialog, not the 24 this shipped with: 24 is on no rung of
              // AppRadius, and the capsule is a floating overlay — the one
              // class of shape allowed to be rounder than a card.
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              border: Border.all(color: colorScheme.surfaceContainerHigh),
              boxShadow: colorScheme.shadowOverlay,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              // No backdrop blur here: the 92%-opaque fill above hides what a
              // blur would show, while the blur still cost a full backdrop
              // readback every frame the capsule was on screen.
              child: AnimatedSize(
                duration: AppMotion.durationOf(context, AppMotion.reveal),
                curve: AppMotion.move,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Animated Spinner / Icon
                        _buildStatusIcon(runningCount, avgProgress, colorScheme),
                        const SizedBox(width: 12),
                        // Text Label
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                runningCount > 0 
                                  ? l10n.runningCount(runningCount)
                                  : l10n.plannedCount(pendingCount),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                ),
                              ),
                              if (pendingCount > 0 && runningCount > 0)
                                Text(
                                  l10n.plannedCount(pendingCount),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(color: colorScheme.outline),
                                ),
                            ],
                          ),
                        ),
                        // Percentage
                        if (runningCount > 0)
                          Text(
                            "${(avgProgress * 100).toInt()}%",
                            // Mono: this number ticks while the user watches
                            // it, and a proportional face shifts the chevron
                            // beside it every time a digit changes width.
                            style: Theme.of(context).textTheme.titleSmall?.mono.copyWith(
                              color: colorScheme.onAccentTint,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                          size: 18,
                          color: colorScheme.outline,
                        ),
                      ],
                    ),
                    // Progress Bar (Linear)
                    if (runningCount > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SmoothProgress(
                          value: avgProgress,
                          builder: (context, v) => LinearProgressIndicator(
                            value: v,
                            minHeight: 3,
                            backgroundColor: colorScheme.surfaceContainer,
                            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                    // Expanded Details
                    if (_isExpanded) ...[
                      const Divider(height: 20),
                      ...activeTasks.take(3).map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            // The task's own kind, not a picture for
                            // everything: a video generation and a batch
                            // rename both used to appear here as images, which
                            // is the one thing a monitor of a mixed queue must
                            // not do.
                            Icon(t.type.glyph, size: 14, color: colorScheme.outline),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t.modelId,
                                // Mono, as `12g` sets it and as every other
                                // model identifier in the app is set. It is a
                                // name to recognise, not prose.
                                style: Theme.of(context).textTheme.labelMedium?.mono,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (t.status == TaskStatus.processing)
                              SizedBox(
                                width: 12,
                                height: 12,
                                // This task's own progress, where it has any.
                                // `12g` draws a filled arc per row; an
                                // indeterminate spinner beside a percentage
                                // that *is* known says less than the ring the
                                // header already shows.
                                child: SmoothProgress(
                                  value: t.progress,
                                  builder: (context, v) =>
                                      CircularProgressIndicator(
                                    value: v,
                                    strokeWidth: 2,
                                    backgroundColor: colorScheme.surfaceContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )),
                      AppButton(
                        label: l10n.viewAll,
                        variant: AppButtonVariant.text,
                        size: AppButtonSize.compact,
                        onPressed: () {
                          context.read<AppState>().navigateToScreen(2);
                          setState(() => _isExpanded = false);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
            ),
          ),
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(int runningCount, double progress, ColorScheme colorScheme) {
    if (runningCount > 0) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SmoothProgress(
              value: progress,
              builder: (context, v) => CircularProgressIndicator(
                value: v,
                strokeWidth: 2.5,
                backgroundColor: colorScheme.surfaceContainer,
              ),
            ),
            Icon(Icons.auto_awesome, size: 12, color: colorScheme.primary),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.layers_outlined, size: 16, color: colorScheme.outline),
    );
  }
}
