import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../services/task_queue_service.dart';
import '../state/app_state.dart';
import '../state/log_state.dart';
import 'log_console.dart';
import 'panel_resizer.dart';
import '../screens/batch/task_queue_screen.dart';

/// Shared run-status console: pulsing status dot, running/pending task
/// summary, and an expandable execution log. Reads entirely from app-wide
/// providers (`AppState`, `TaskQueueService`), so it can be dropped onto any
/// screen's `Scaffold.bottomNavigationBar` unchanged.
class AppRunConsole extends StatefulWidget {
  const AppRunConsole({super.key});

  @override
  State<AppRunConsole> createState() => _AppRunConsoleState();
}

class _AppRunConsoleState extends State<AppRunConsole> {
  /// How far past the height limits a drag keeps its bookkeeping, so the
  /// handle re-engages where the pointer actually is instead of the moment it
  /// reverses. Same value and reasoning as the workbench's panel slack.
  static const double _kDragSlack = 24;

  double _height = 200;
  bool _heightInitialized = false;

  /// The drag's own accumulator, allowed to run [_kDragSlack] past the limits
  /// while a drag is in flight. `null` when no drag is active.
  double? _dragHeight;

  @override
  Widget build(BuildContext context) {
    if (!_heightInitialized) {
      _heightInitialized = true;
      _height = Provider.of<AppState>(context, listen: false).consoleHeight;
    }
    final isConsoleExpanded = context.select<AppState, bool>((s) => s.isConsoleExpanded);
    // Log-derived values come off LogState, which notifies on its own coalesced
    // schedule rather than through AppState. See LogState.
    final hasErrors = context.select<LogState, bool>((s) => s.hasErrors);
    final lastLogMessage =
        context.select<LogState, String?>((s) => s.logs.isEmpty ? null : s.logs.last.message);
    final queue = context.watch<TaskQueueService>();
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isMobile = Responsive.isMobile(context);

    final pendingCount = queue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = queue.runningCount;
    // Read off the queue rather than a mirrored flag on AppState. The mirror
    // existed only so this one line could be a selector, and keeping it in sync
    // is what made AppState notify on every queue tick.
    final isProcessing = runningCount > 0;
    final hasTasks = pendingCount > 0 || runningCount > 0;
    final avgProgress = _avgProgress(queue);

    final statusBar = InkWell(
          onTap: () {
            if (isMobile) {
              _showTaskQueueSheet(context);
            } else {
              context.read<AppState>().setConsoleExpanded(!isConsoleExpanded);
            }
          },
          child: Stack(
            children: [
              Container(
                // `A1 16a` draws the strip at 32 (§1 「状态栏 30px」 agrees to
                // within a rounding). It shipped at 40, which is eight pixels
                // of window spent on a bar that carries one line of 11.5px
                // text and a 23px pill.
                height: isMobile ? 40 : 32,
                decoration: isMobile
                    ? BoxDecoration(
                        color: colorScheme.surface,
                        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(90))),
                      )
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildStatusIndicator(isProcessing, hasErrors, colorScheme),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        l10n.executionLogs,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),

                    // Task summary — shown on every breakpoint so the count /
                    // running / progress info isn't lost now that the floating
                    // capsule is hidden on the workbench.
                    if (hasTasks) ...[
                      const SizedBox(width: 12),
                      Container(width: 1, height: 16, color: colorScheme.outlineVariant.withAlpha(120)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: _buildTaskSummary(runningCount, pendingCount, avgProgress, l10n, colorScheme),
                      ),
                    ],

                    // While tasks run, suppress the single-line log preview: with
                    // parallel tasks it flickers between interleaved messages.
                    Expanded(
                      child: (!hasTasks && !isMobile && lastLogMessage != null)
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                lastLogMessage,
                                style: Theme.of(context).textTheme.labelMedium?.mono.copyWith(
                                  color: colorScheme.onSurfaceVariant.withAlpha(160),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(width: 8),
                    Icon(
                      isMobile
                          ? Icons.assignment_outlined
                          : (isConsoleExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                      size: 16,
                      color: isMobile ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (isProcessing)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: avgProgress > 0 ? avgProgress : null,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
        );

    if (isMobile) {
      return Column(mainAxisSize: MainAxisSize.min, children: [statusBar]);
    }

    // Desktop: a strip across the bottom of the window, flush with the
    // columns above it. It was an inset card with an 8px margin, which stopped
    // making sense the moment those columns stopped being cards — a rounded
    // slab under three square-cornered columns reads as a different screen.
    //
    // Every screen that hosts a console is on the column language or headed
    // there, so this changes with the machinery rather than per screen.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isConsoleExpanded)
          PanelResizer(
            axis: Axis.vertical,
            shape: PanelShape.column,
            // The accumulator, not the height, absorbs the drag: clamping the
            // accumulator itself meant that after dragging 200px past a limit
            // the panel started moving the instant the pointer reversed, with
            // the pointer still 200px from the handle.
            onDrag: (dy) => setState(() {
              _dragHeight = ((_dragHeight ?? _height) - dy)
                  .clamp(100.0 - _kDragSlack, 600.0 + _kDragSlack);
              _height = _dragHeight!.clamp(100.0, 600.0);
            }),
            onDragEnd: () {
              setState(() => _dragHeight = null);
              Provider.of<AppState>(context, listen: false).setConsoleHeight(_height);
            },
          )
        else
          // Collapsed there is no gutter to drag, so the hairline is drawn
          // rather than dragged — without it the status bar and the column
          // above it run together into one field of the same colour.
          Container(height: 1, color: colorScheme.surfaceContainerHigh),
        Material(
          color: colorScheme.surfaceContainerLow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              statusBar,
              // The console used to hard-insert its full height between two
              // frames; AppMotion.reveal exists for exactly this disclosure.
              // Duration collapses to zero while the resizer is dragging so
              // the height tracks the pointer 1:1 — the animation is for the
              // expand/collapse toggle, never for the drag.
              ClipRect(
                child: AnimatedSize(
                  duration: _dragHeight != null
                      ? Duration.zero
                      : AppMotion.durationOf(context, AppMotion.reveal),
                  curve: AppMotion.enter,
                  alignment: Alignment.topCenter,
                  child: isConsoleExpanded
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Divider(height: 1),
                            SizedBox(
                              height: _height,
                              child: const LogConsoleWidget(),
                            ),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(bool isProcessing, bool hasErrors, ColorScheme colorScheme) {
    Color color = colorScheme.outline;
    if (isProcessing) color = colorScheme.primary;
    if (hasErrors) color = colorScheme.error;

    return _StatusDot(color: color, pulsing: isProcessing);
  }

  double _avgProgress(TaskQueueService queue) {
    final active = queue.queue.where((t) => t.status == TaskStatus.processing).toList();
    if (active.isEmpty) return 0;
    double total = 0;
    int count = 0;
    for (final t in active) {
      if (t.progress != null) {
        total += t.progress!;
        count++;
      }
    }
    return count > 0 ? total / count : 0;
  }

  Widget _buildTaskSummary(
    int runningCount,
    int pendingCount,
    double avgProgress,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final pct = (avgProgress * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primary.withAlpha(18),
        // A pill, per `16a` — and per §1, where every badge that states a
        // count or a state is one. At radius 8 this was the only rounded
        // rectangle in a status bar of round things.
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (runningCount > 0) ...[
            Text(
              l10n.runningCount(runningCount),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.primary),
            ),
            const SizedBox(width: 7),
            // A bar rather than the 11px ring this replaced: at that size a
            // ring shows roughly "some" progress, while a track the eye can
            // read left-to-right shows how far along the batch actually is.
            // Indeterminate until the first task reports, so a queue that has
            // started but not measured itself does not read as stalled at 0%.
            SizedBox(
              width: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: avgProgress > 0 ? avgProgress : null,
                  minHeight: 4,
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.18),
                  color: colorScheme.primary,
                ),
              ),
            ),
            if (avgProgress > 0) ...[
              const SizedBox(width: 7),
              Text(
                '$pct%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.primary),
              ),
            ],
          ],
          if (runningCount > 0 && pendingCount > 0) _dotSeparator(colorScheme),
          if (pendingCount > 0) ...[
            Icon(Icons.schedule, size: 13, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              l10n.plannedCount(pendingCount),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dotSeparator(ColorScheme colorScheme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(color: colorScheme.onSurfaceVariant.withAlpha(120), shape: BoxShape.circle),
        ),
      );

  void _showTaskQueueSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The queue screen draws task cards on a canvas; on `surface` the cards
      // would be the same colour as the sheet they sit on.
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return const TaskQueueScreen();
        },
      ),
    );
  }
}

/// The run console's status light, which breathes while work is in flight.
///
/// Its own widget so the ticker's lifetime matches the thing it is animating.
/// The controller used to live on the console and `repeat()` unconditionally
/// from `initState`, which kept a ticker running — and therefore the engine
/// waking for every vsync — for the entire life of the app, including the vast
/// majority of the time when `isProcessing` was false and the pulse was not
/// even mounted. It also localises the 60fps rebuild to this 8px dot rather
/// than the console row around it.
class _StatusDot extends StatefulWidget {
  final Color color;
  final bool pulsing;

  const _StatusDot({required this.color, required this.pulsing});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _opacity = Tween<double>(begin: 1.0, end: 0.4)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.85)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  /// Read in [didChangeDependencies] — initState cannot see MediaQuery.
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = AppMotion.prefersReduced(context);
    if (reduced != _reduced) {
      _reduced = reduced;
      _syncTicker();
    } else if (!_controller.isAnimating) {
      // First build lands here (initState defers to us); later calls with an
      // unchanged flag are no-ops either way.
      _syncTicker();
    }
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulsing != widget.pulsing) _syncTicker();
  }

  void _syncTicker() {
    // Reduce-motion counts as not pulsing: this loop is the one motion in the
    // app that never ends, which makes it the strongest case that setting
    // has. The colour and the glow still say "working" without movement.
    if (widget.pulsing && !_reduced) {
      _controller.repeat(reverse: true);
    } else {
      // `stop` rather than `reset`: nothing reads the value while idle, and
      // leaving it where it was avoids a visible jump if work resumes.
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: widget.pulsing
            ? [BoxShadow(color: widget.color.withAlpha(100), blurRadius: 4, spreadRadius: 1)]
            : null,
      ),
    );

    if (!widget.pulsing || _reduced) return dot;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: Opacity(opacity: _opacity.value, child: child),
      ),
      child: dot,
    );
  }
}
