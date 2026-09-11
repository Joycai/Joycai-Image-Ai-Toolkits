import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../models/log_entry.dart';
import '../services/task_queue_service.dart';
import '../state/app_state.dart';
import '../state/log_state.dart';
import 'app_breathing_dot.dart';
import 'log_console.dart';
import '../screens/batch/task_queue_screen.dart';

/// Shared run-status console: status dot, running/planned task summary, the
/// last log line, and an expandable execution log. Reads entirely from
/// app-wide providers (`AppState`, `LogState`, `TaskQueueService`), so it can
/// be dropped onto any screen's `Scaffold.bottomNavigationBar` unchanged.
///
/// `A1 · 1a / 1c / 1d`: a 32px column-coloured strip (40 on a phone) under a
/// hairline — dot, tracked `EXECUTION LOGS` caption, summary, the mono tail
/// line pushed right, and a chevron. Expanded, the log panel below it is the
/// same opaque column ground, with its height dragged from the top edge.
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

  /// The gap between every item on the strip (`gap:10px`).
  static const double _kGap = AppSpace.s10;

  /// The longest stretch of a message the tail line lays out. The strip shows
  /// one ellipsised line, and a streamed reply can be thousands of characters
  /// long; measuring all of it on every chunk buys nothing that is visible.
  static const int _kTailRunes = 240;

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
    final lastLog = context.select<LogState, LogEntry?>((s) => s.logs.isEmpty ? null : s.logs.last);
    final queue = context.watch<TaskQueueService>();
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isMobile = Responsive.isMobile(context);

    final pendingCount = queue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = queue.runningCount;
    final failedCount = queue.queue.where((t) => t.status == TaskStatus.failed).length;
    // Read off the queue rather than a mirrored flag on AppState. The mirror
    // existed only so this one line could be a selector, and keeping it in sync
    // is what made AppState notify on every queue tick.
    final isProcessing = runningCount > 0;
    final hasTasks = pendingCount > 0 || runningCount > 0;
    final avgProgress = _avgProgress(queue);

    // While tasks run, suppress the single-line log preview: with parallel
    // tasks it flickers between interleaved messages. Phones have no room
    // for it beside the summary.
    final tail = (!hasTasks && !isMobile) ? lastLog : null;

    Widget statusBar({required bool topRule}) => _StatusBar(
          height: isMobile ? AppSize.large : AppSize.control,
          topRule: topRule,
          hasErrors: hasErrors,
          isProcessing: isProcessing,
          summary: _summary(runningCount, pendingCount, avgProgress, hasErrors ? failedCount : 0, l10n),
          tail: tail,
          // On a phone the strip opens the queue sheet, which rises; on a
          // desktop it discloses the log panel above-and-below it.
          chevron: (!isMobile && isConsoleExpanded) ? Icons.expand_more : Icons.expand_less,
          onTap: () {
            if (isMobile) {
              _showTaskQueueSheet(context);
            } else {
              context.read<AppState>().setConsoleExpanded(!isConsoleExpanded);
            }
          },
        );

    if (isMobile) {
      return Material(
        color: colorScheme.surfaceContainerLow,
        child: statusBar(topRule: true),
      );
    }

    // Desktop: a strip across the bottom of the window, flush with the
    // columns above it. Every screen that hosts a console is on the column
    // language, so this changes with the machinery rather than per screen.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Expanded, the top hairline moves onto the drag handle — the
        // strip's own rule would otherwise sit a handle's height below the
        // edge the pointer is dragging.
        if (isConsoleExpanded)
          _ConsoleResizeHandle(
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
          ),
        Material(
          // `展开面板 = 不透明 col`: the panel is opaque, never the aurora.
          color: colorScheme.surfaceContainerLow,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              statusBar(topRule: !isConsoleExpanded),
              // Duration collapses to zero while the handle is dragging so
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

  /// `2 running · 1 planned · 64%`, `1 failed · Idle` (`A1 · 1a / 1c / 1d`).
  ///
  /// The percentage appears only once a running task has reported progress,
  /// so a queue that has started but not measured itself does not read as
  /// stalled at 0%. Failures are counted only while the log still carries an
  /// error, so a failure the user has already dealt with does not linger.
  String? _summary(
    int runningCount,
    int pendingCount,
    double avgProgress,
    int failedCount,
    AppLocalizations l10n,
  ) {
    final idle = runningCount == 0 && pendingCount == 0;
    final parts = <String>[
      if (failedCount > 0) l10n.consoleFailedCount(failedCount),
      if (runningCount > 0) l10n.runningCount(runningCount),
      if (pendingCount > 0) l10n.plannedCount(pendingCount),
      if (runningCount > 0 && avgProgress > 0) '${(avgProgress * 100).round()}%',
      if (idle) l10n.consoleIdle,
    ];
    return parts.join(' · ');
  }

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

/// The collapsed strip itself. Paints no ground of its own — the [Material]
/// around it does, so the tap's ink lands on the column colour.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.height,
    required this.topRule,
    required this.hasErrors,
    required this.isProcessing,
    required this.summary,
    required this.tail,
    required this.chevron,
    required this.onTap,
  });

  final double height;
  final bool topRule;
  final bool hasErrors;
  final bool isProcessing;
  final String? summary;
  final LogEntry? tail;
  final IconData chevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // `A1 spec` 「状态点：运行 --p 呼吸 / 失败 --err / 空闲 ink3」. A failure
    // outranks a run in progress: the red is the thing to notice, and it
    // stops being true the moment a task next succeeds (LogState).
    final Color dotColor;
    final bool breathing;
    if (hasErrors) {
      dotColor = colorScheme.error;
      breathing = false;
    } else if (isProcessing) {
      dotColor = colorScheme.primary;
      breathing = true;
    } else {
      dotColor = colorScheme.outline;
      breathing = false;
    }

    final tail = this.tail;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: topRule
            ? BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outlineVariant)))
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            AppBreathingDot(color: dotColor, breathing: breathing),
            const SizedBox(width: _AppRunConsoleState._kGap),
            Text(
              AppLocalizations.of(context)!.executionLogs,
              maxLines: 1,
              style: textTheme.labelSmall?.copyWith(
                letterSpacing: AppType.trackedLabelSpacing,
                color: colorScheme.onAccentTint,
              ),
            ),
            const SizedBox(width: _AppRunConsoleState._kGap),
            // One flexible region for summary and tail, so whichever is
            // showing gets all the room the caption and chevron leave.
            Expanded(
              child: Row(
                children: [
                  if (summary != null)
                    Flexible(
                      child: Text(
                        summary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          // The percentage ticks while it runs; proportional
                          // figures would make the whole summary shimmy.
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  if (summary != null && tail != null) const SizedBox(width: _AppRunConsoleState._kGap),
                  if (tail != null)
                    Expanded(
                      child: Text(
                        _tailText(tail),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: textTheme.labelSmall?.mono.copyWith(
                          fontWeight: FontWeight.w400,
                          color: tail.level == 'ERROR' ? colorScheme.error : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: _AppRunConsoleState._kGap),
            Icon(chevron, size: AppSize.iconMd, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// `14:02:11 [info] gemini-2.5-flash-image · streaming chunk 12`, flattened
  /// onto one line.
  static String _tailText(LogEntry log) {
    final head = String.fromCharCodes(log.message.runes.take(_AppRunConsoleState._kTailRunes));
    final message = head.replaceAll(RegExp(r'\s+'), ' ').trim();
    return '${logClockOf(log.timestamp)} [${log.level.toLowerCase()}] $message';
  }
}

/// The top edge of the expanded console: its hairline, and the strip the
/// pointer drags to set the panel's height.
///
/// Drawn here rather than by `PanelResizer`, whose column boundary is a
/// softer rule than the strip's own `border-top`: collapsing and expanding
/// would otherwise change the line's colour. The grip is the hairline at rest
/// and the accent while it is under the pointer or being dragged.
class _ConsoleResizeHandle extends StatefulWidget {
  const _ConsoleResizeHandle({required this.onDrag, required this.onDragEnd});

  /// The vertical drag delta; positive is the pointer moving down.
  final ValueChanged<double> onDrag;

  /// The drag ended — the moment to persist the height.
  final VoidCallback onDragEnd;

  /// A hit target, not a gap: the rule is one pixel, the grip three.
  static const double _kHeight = 9;

  @override
  State<_ConsoleResizeHandle> createState() => _ConsoleResizeHandleState();
}

class _ConsoleResizeHandleState extends State<_ConsoleResizeHandle> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovering || _dragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        onVerticalDragCancel: () => setState(() => _dragging = false),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: SizedBox(
            height: _ConsoleResizeHandle._kHeight,
            width: double.infinity,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.durationOf(context, AppMotion.hover),
                curve: AppMotion.quick,
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: active ? colorScheme.primary : colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
