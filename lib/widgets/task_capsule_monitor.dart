import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../core/task_type_glyph.dart';
import '../l10n/app_localizations.dart';
import '../services/task_queue_service.dart';
import '../state/app_state.dart';
import 'app_breathing_dot.dart';
import 'glass/app_glass.dart';
import 'shell/app_destinations.dart';
import 'shell/phone_dock.dart';
import 'smooth_progress.dart';

/// The floating summary of the queue (`01 · 1d` collapsed, `1e` expanded,
/// `1g` phone): G2 glass, 196 wide at r16 collapsed, 300 at r22 expanded, the
/// phone's full width less 16 each side, parked above the dock.
///
/// Hidden on the workbench and the task queue, which already show the queue in
/// their run console — one report of the queue per screen.
class TaskCapsuleMonitor extends StatefulWidget {
  const TaskCapsuleMonitor({super.key});

  @override
  State<TaskCapsuleMonitor> createState() => _TaskCapsuleMonitorState();
}

class _TaskCapsuleMonitorState extends State<TaskCapsuleMonitor>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  Offset? _offset;

  /// Apple's `spring(duration:bounce:)` at the audit's recommended setting. A
  /// 0.2 bounce is one barely-seen overshoot of about 1.5% of the travel — 6px
  /// on a 400px throw, well inside the 16px edge inset.
  ///
  /// Its 500ms is a *settling* time, not a transition duration: the capsule
  /// covers most of the distance in the first third, and unlike a fixed curve
  /// it leaves at the speed it was thrown. The M ladder's ceiling is a budget
  /// for transitions and does not apply.
  static final SpringDescription _kSettle = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 500),
    bounce: 0.2,
  );

  /// Unbounded: a spring overshoots past 1 before it settles.
  late final AnimationController _settle = AnimationController.unbounded(vsync: this);
  Offset? _settleFrom;
  Offset? _settleTo;

  /// Where the capsule actually is this frame. Mid-flight that is not
  /// [_offset], which is already the target.
  Offset get _renderOffset {
    final Offset? from = _settleFrom;
    final Offset? to = _settleTo;
    if (from == null || to == null || !_settle.isAnimating) return _offset!;
    return Offset.lerp(from, to, _settle.value)!;
  }

  /// Hands the throw to the spring: [target] is where the capsule parks,
  /// [velocity] the gesture's own speed in logical pixels per second.
  void _settleAt(Offset target, Offset velocity) {
    final Offset from = _renderOffset;
    if (AppMotion.prefersReduced(context) || from == target) {
      setState(() {
        _offset = target;
        _settleFrom = null;
        _settleTo = null;
      });
      return;
    }
    final Offset travel = target - from;
    final double distance = travel.distance;
    // The simulation runs on t in [0, 1], so it wants the throw's component
    // along the travel expressed in travels per second. `dy` flips: the
    // gesture's y grows downward, [_offset]'s grows upward.
    final double v = (velocity.dx * travel.dx - velocity.dy * travel.dy) / (distance * distance);
    setState(() {
      _settleFrom = from;
      _settleTo = target;
      _offset = target;
    });
    _settle
      ..value = 0
      ..animateWith(SpringSimulation(_kSettle, 0, 1, v));
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// Drag bookkeeping, allowed [_kDragSlack] past the bounds so the capsule
  /// re-engages where the pointer is after being pushed into an edge.
  static const double _kDragSlack = 24;
  Offset? _dragOffset;
  bool _pressed = false;

  static const double _kEdgeInset = 16;
  static const double _collapsedWidth = 196;
  static const double _expandedWidth = 300;

  /// Where a flick would come to rest — (v/1000)·d/(1−d), d = 0.998.
  static double _project(double velocity) => velocity / 1000 * 0.998 / (1 - 0.998);

  /// Where the capsule parks, as (from the left, from the **bottom**).
  ///
  /// Anchored by its bottom edge so opening it grows it *up* into space that
  /// is there, rather than off the bottom of the window.
  void _initPosition(Size screenSize, bool isPhone, double dockClearance) {
    if (_offset != null) return;
    _offset = isPhone
        ? Offset(_kEdgeInset, dockClearance)
        : Offset(screenSize.width - _collapsedWidth - _kEdgeInset, _kEdgeInset);
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<TaskQueueService>();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isPhone = Responsive.isMobile(context);
    final screenSize = MediaQuery.sizeOf(context);

    _initPosition(screenSize, isPhone, PhoneDock.clearanceOf(context));

    final pendingCount = queue.queue.where((t) => t.status == TaskStatus.pending).length;
    final activeTasks = queue.queue.where((t) => t.status == TaskStatus.processing).toList();
    final runningCount = activeTasks.length;

    final int screen = context.select<AppState, int>((s) => s.activeScreenIndex);
    final bool queueIsOnScreen =
        screen == AppDestination.workbench.index || screen == AppDestination.tasks.index;
    final visible = (pendingCount > 0 || runningCount > 0) && !queueIsOnScreen;

    double avgProgress = 0;
    final withProgress = activeTasks.where((t) => t.progress != null).toList();
    if (withProgress.isNotEmpty) {
      avgProgress =
          withProgress.fold<double>(0, (sum, t) => sum + t.progress!) / withProgress.length;
    }

    final capsuleWidth = isPhone
        ? (screenSize.width - _kEdgeInset * 2)
        : (_isExpanded ? _expandedWidth : _collapsedWidth);

    final maxX = screenSize.width - capsuleWidth;
    final maxY = screenSize.height - 80;

    final String headline;
    if (runningCount > 0) {
      headline = pendingCount > 0 && isPhone
          ? '${l10n.runningCount(runningCount)} · ${l10n.plannedCount(pendingCount)}'
          : l10n.runningCount(runningCount);
    } else {
      headline = l10n.plannedCount(pendingCount);
    }

    final Widget capsule = IgnorePointer(
      ignoring: !visible,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: GestureDetector(
          onPanStart: (_) => setState(() {
            // Grab it where it is: a capsule caught mid-flight must not jump
            // to its target under the finger.
            _offset = _renderOffset;
            _settle.stop();
            _settleFrom = null;
            _settleTo = null;
            _dragOffset = _offset;
          }),
          onPanUpdate: (details) {
            setState(() {
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
            final v = details.velocity.pixelsPerSecond;
            final projected = Offset(
              _offset!.dx + _project(v.dx),
              _offset!.dy - _project(v.dy),
            );
            final double snapX = (projected.dx + capsuleWidth / 2) < screenSize.width / 2
                ? _kEdgeInset
                : maxX - _kEdgeInset;
            final Offset target = Offset(
              v.distance < 100 ? _offset!.dx : snapX,
              projected.dy.clamp(_kEdgeInset, maxY),
            );
            setState(() => _dragOffset = null);
            _settleAt(target, v);
          },
          onPanCancel: () => setState(() => _dragOffset = null),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: AppMotion.sceneOf(context),
            curve: AppMotion.emphasized,
            child: AnimatedSlide(
              // `00 · 1e` M3: floating pieces enter from 12px below.
              offset: visible ? Offset.zero : const Offset(0, 0.25),
              duration: AppMotion.sceneOf(context),
              curve: AppMotion.emphasized,
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedContainer(
                  duration: AppMotion.sceneOf(context),
                  curve: AppMotion.emphasized,
                  width: capsuleWidth,
                  child: AppGlass(
                    grade: GlassGrade.float,
                    pressed: _pressed,
                    borderRadius: BorderRadius.circular(
                        _isExpanded ? AppRadius.dialog : AppRadius.lg),
                    padding: EdgeInsets.fromLTRB(isPhone ? 12 : 10, 8, isPhone ? 12 : 10, 6),
                    child: Builder(builder: (context) {
                      final glass = GlassInk.maybeOf(context);
                      final ink = glass?.ink ?? scheme.onSurface;
                      final ink2 = glass?.ink2 ?? scheme.onSurfaceVariant;
                      final edge = glass?.edge ?? scheme.outlineVariant;
                      final track = (glass?.reduced ?? false)
                          ? scheme.surfaceContainerHighest
                          : ink.withValues(alpha: 0.14);
                      final headStyle = (isPhone ? textTheme.bodyMedium! : textTheme.bodySmall!)
                          .metricsOnly
                          .copyWith(fontWeight: FontWeight.w600);
                      final numberStyle =
                          (isPhone ? textTheme.bodySmall! : textTheme.labelSmall!).mono.copyWith(
                                color: ink2,
                                fontWeight: FontWeight.w400,
                              );

                      return AnimatedSize(
                        duration: AppMotion.sceneOf(context),
                        curve: AppMotion.emphasized,
                        alignment: Alignment.bottomCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                AppBreathingDot(
                                  color: runningCount > 0 ? scheme.primary : ink2,
                                  breathing: runningCount > 0,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    headline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: headStyle,
                                  ),
                                ),
                                if (runningCount > 0)
                                  Text('${(avgProgress * 100).toInt()}%', style: numberStyle),
                                const SizedBox(width: 4),
                                Icon(
                                  _isExpanded ? Icons.expand_more : Icons.expand_less,
                                  size: AppSize.iconMd,
                                ),
                              ],
                            ),
                            if (runningCount > 0) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: SmoothProgress(
                                  value: avgProgress,
                                  builder: (context, v) => LinearProgressIndicator(
                                    value: v,
                                    minHeight: 3,
                                    backgroundColor: track,
                                    valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                                  ),
                                ),
                              ),
                            ],
                            if (_isExpanded) ...[
                              Container(
                                height: 1,
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                color: edge,
                              ),
                              if (pendingCount > 0 && runningCount > 0 && !isPhone)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    l10n.plannedCount(pendingCount),
                                    style: textTheme.bodySmall!.metricsOnly.copyWith(color: ink2),
                                  ),
                                ),
                              for (final t in activeTasks.take(3))
                                SizedBox(
                                  height: 28,
                                  child: Row(
                                    children: [
                                      Icon(t.type.glyph, size: AppSize.iconSm, color: ink2),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          t.modelId,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.labelSmall!.mono.copyWith(
                                            color: ink,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: SmoothProgress(
                                          value: t.progress,
                                          builder: (context, v) => CircularProgressIndicator(
                                            value: v,
                                            strokeWidth: 2,
                                            color: scheme.primary,
                                            backgroundColor: track,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    context
                                        .read<AppState>()
                                        .navigateToScreen(AppDestination.tasks.index);
                                    setState(() => _isExpanded = false);
                                  },
                                  child: Text(l10n.viewAll),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: 0,
      bottom: 0,
      // Paint, not layout: the capsule is laid out once and only moved.
      child: AnimatedBuilder(
        animation: _settle,
        child: capsule,
        builder: (context, child) {
          final Offset o = _renderOffset;
          return Transform.translate(offset: Offset(o.dx, -o.dy), child: child);
        },
      ),
    );
  }
}
