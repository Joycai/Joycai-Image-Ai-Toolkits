import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/task_queue_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/log_console.dart';
import '../../../widgets/panel_resizer.dart';
import '../../batch/task_queue_screen.dart';

class WorkbenchBottomConsole extends StatefulWidget {
  const WorkbenchBottomConsole({super.key});

  @override
  State<WorkbenchBottomConsole> createState() => _WorkbenchBottomConsoleState();
}

class _WorkbenchBottomConsoleState extends State<WorkbenchBottomConsole>
    with SingleTickerProviderStateMixin {
  double _height = 200;
  bool _heightInitialized = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseOpacity;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseOpacity = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_heightInitialized) {
      _heightInitialized = true;
      _height = Provider.of<AppState>(context, listen: false).consoleHeight;
    }
    final isConsoleExpanded = context.select<AppState, bool>((s) => s.isConsoleExpanded);
    final hasErrors = context.select<AppState, bool>((s) => s.hasErrors);
    final isProcessing = context.select<AppState, bool>((s) => s.isProcessing);
    final lastLogMessage = context.select<AppState, String?>((s) => s.logs.isEmpty ? null : s.logs.last.message);
    final queue = context.watch<TaskQueueService>();
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isMobile = Responsive.isMobile(context);

    final pendingCount = queue.queue.where((t) => t.status == TaskStatus.pending).length;
    final runningCount = queue.runningCount;
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
                height: 40,
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
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
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
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
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

    // Desktop: the console is an inset card on the canvas. The resize gutter
    // sits above the card while expanded; collapsed, a plain 8px gap matches
    // the canvas padding of the panel row above.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isConsoleExpanded)
          PanelResizer(
            axis: Axis.vertical,
            onDrag: (dy) => setState(() {
              _height = (_height - dy).clamp(100.0, 600.0);
            }),
            onDragEnd: () =>
                Provider.of<AppState>(context, listen: false).setConsoleHeight(_height),
          )
        else
          const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Material(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              statusBar,
              if (isConsoleExpanded) ...[
                const Divider(height: 1),
                SizedBox(
                  height: _height,
                  child: const LogConsoleWidget(),
                ),
              ],
            ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(bool isProcessing, bool hasErrors, ColorScheme colorScheme) {
    Color color = colorScheme.outline;
    if (isProcessing) color = colorScheme.primary;
    if (hasErrors) color = colorScheme.error;

    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: isProcessing
            ? [BoxShadow(color: color.withAlpha(100), blurRadius: 4, spreadRadius: 1)]
            : null,
      ),
    );

    if (!isProcessing) return dot;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) => Transform.scale(
        scale: _pulseScale.value,
        child: Opacity(opacity: _pulseOpacity.value, child: child),
      ),
      child: dot,
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

  Widget _buildTaskSummary(
    int runningCount,
    int pendingCount,
    double avgProgress,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final pct = (avgProgress * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primary.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (runningCount > 0) ...[
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                value: avgProgress > 0 ? avgProgress : null,
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              l10n.runningCount(runningCount),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colorScheme.primary),
            ),
            if (avgProgress > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$pct%',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: colorScheme.primary),
              ),
            ],
          ],
          if (runningCount > 0 && pendingCount > 0) _dotSeparator(colorScheme),
          if (pendingCount > 0) ...[
            Icon(Icons.schedule, size: 13, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              l10n.plannedCount(pendingCount),
              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
