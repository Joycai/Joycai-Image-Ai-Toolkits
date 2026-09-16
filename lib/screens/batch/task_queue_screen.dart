import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../services/tasks/task_list_ordering.dart';
import '../../services/tasks/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/task_list_state.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_dialog.dart';
import '../../widgets/ui/app_icon_button.dart';
import '../../widgets/tasks/app_run_console.dart';
import '../../widgets/ui/app_segmented_control.dart';
import '../../widgets/ui/app_switch.dart';
import '../../widgets/glass/app_glass.dart';
import '../../widgets/glass/glass_controls.dart';
import '../../widgets/ui/scroll_edge_fade.dart';
import '../../widgets/shell/app_destinations.dart';
import 'task_queue_card.dart';

part 'task_queue/task_queue_bands.dart';
part 'task_queue/task_queue_phone.dart';
part 'task_queue/task_queue_wide_header.dart';

/// The batch task queue (`B2`).
///
/// ≥600: a 72px header (title, the five counts, the queue-wide actions) and a
/// 44px filter row on the column colour, over a list of task cards on the
/// aurora, with the run console at the foot. <600: a G1 top bar with one ⋮, an
/// abbreviated counts row, a 58px chip strip and compact cards.
///
/// The floating task capsule stays off this screen — the queue's own header
/// already reports what the capsule would. The shell decides that
/// (`task_capsule_monitor.dart`), not this file.
/// Raises the queue in a modal sheet.
///
/// Lives with the screen it presents rather than in [AppRunConsole], which
/// takes it as `onExpand`: a shared widget cannot reach into a feature screen.
/// Top-level, so the hosts can pass it as a tear-off inside a `const`
/// constructor.
void showTaskQueueSheet(BuildContext context) {
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

class TaskQueueScreen extends StatefulWidget {
  const TaskQueueScreen({super.key});

  @override
  State<TaskQueueScreen> createState() => _TaskQueueScreenState();
}

/// The queue in five figures.
class _Counts {
  _Counts(List<TaskItem> queue) : total = queue.length {
    for (final task in queue) {
      switch (task.status) {
        case TaskStatus.processing:
          running++;
        case TaskStatus.pending:
          pending++;
        case TaskStatus.completed:
          done++;
        case TaskStatus.failed:
          failed++;
        case TaskStatus.cancelled:
          cancelled++;
      }
    }
  }

  final int total;
  int running = 0;
  int pending = 0;
  int done = 0;
  int failed = 0;
  int cancelled = 0;

  /// What 清除已完成 removes: every settled task.
  int get settled => done + failed + cancelled;

  /// What 清除全部 is offered for: anything not running.
  int get clearable => total - running;
}

/// How much of the header's action group fits beside the title block.
enum _HeaderFit { labelled, icons, folded }

class _TaskQueueScreenState extends State<TaskQueueScreen> {
  /// Which cards are open, by task id.
  ///
  /// Here rather than in each card: a task crosses the pinned seam the moment
  /// it finishes and moves when the sort flips, and a list builder that
  /// rebuilds or recycles its card must not lose — or hand to a neighbour —
  /// whether it was open.
  final Set<String> _expanded = <String>{};

  void _toggle(String id) => setState(() {
        if (!_expanded.remove(id)) _expanded.add(id);
      });

  @override
  Widget build(BuildContext context) {
    // The queue is what this screen renders, so it subscribes to the queue
    // itself; AppState no longer re-broadcasts queue ticks.
    context.watch<TaskQueueService>();
    // Filter, sort and pinning live in TaskListState: the shell rebuilds this
    // screen on every visit, and a filter kept here reset each time.
    final listState = context.watch<TaskListState>();
    final appState = Provider.of<AppState>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final queue = appState.taskQueue.queue;

    // Forget cards whose task has left the queue.
    final ids = {for (final task in queue) task.id};
    _expanded.retainWhere(ids.contains);

    // Embedded in the phone console's bottom sheet: the sheet is the console,
    // so a console inside it would be the console twice.
    final inBottomSheet = context.findAncestorWidgetOfExactType<BottomSheet>() != null;

    final counts = _Counts(queue);
    final tasks = listState.arrange(queue);
    final positions = _queuePositions(queue);

    if (Responsive.isMobile(context)) {
      return _buildPhone(context, queue, counts, tasks, positions, listState, l10n,
          inBottomSheet: inBottomSheet);
    }

    final content = _buildWide(context, queue, counts, tasks, positions, listState, l10n);
    if (inBottomSheet) return content;
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: const AppRunConsole(onExpand: showTaskQueueSheet),
      body: content,
    );
  }

  /// Each pending task's 1-based place in execution (FIFO) order, computed
  /// once per build rather than once per row.
  static Map<String, int> _queuePositions(List<TaskItem> queue) {
    final positions = <String, int>{};
    var next = 0;
    for (final task in queue) {
      if (task.status == TaskStatus.pending) positions[task.id] = ++next;
    }
    return positions;
  }

  // ── Wide form (≥600) ────────────────────────────────────────────────────────

  Widget _buildWide(
    BuildContext context,
    List<TaskItem> queue,
    _Counts counts,
    ArrangedTasks tasks,
    Map<String, int> positions,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ColumnBand(height: 72, child: _buildHeader(context, counts, l10n)),
        _ColumnBand(height: 44, child: _buildFilterRow(context, queue, listState, l10n)),
        Expanded(
          child: tasks.isEmpty
              ? _buildEmptyOrFiltered(context, queue, listState, l10n)
              : _buildList(
                  context,
                  tasks,
                  positions,
                  l10n,
                  phone: false,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                ),
        ),
      ],
    );
  }

  // ── List ────────────────────────────────────────────────────────────────────

  Widget _buildList(
    BuildContext context,
    ArrangedTasks tasks,
    Map<String, int> positions,
    AppLocalizations l10n, {
    required bool phone,
    required EdgeInsets padding,
  }) {
    final statusWidth = phone ? 0.0 : taskStatusColumnWidth(context);

    Widget card(TaskItem task) => Padding(
          key: ValueKey(task.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: TaskQueueCard(
            task: task,
            position: positions[task.id] ?? 0,
            expanded: _expanded.contains(task.id),
            onToggle: () => _toggle(task.id),
            statusColumnWidth: statusWidth,
            compact: phone,
          ),
        );

    final pinned = tasks.pinned.length;
    final dividers = tasks.hasDivider ? 1 : 0;
    return ListView.builder(
      padding: padding,
      itemCount: tasks.length + dividers,
      itemBuilder: (context, index) {
        if (index < pinned) return card(tasks.pinned[index]);
        final below = index - pinned;
        if (dividers == 1 && below == 0) {
          return _GroupDivider(label: l10n.restByCreatedTime);
        }
        return card(tasks.rest[below - dividers]);
      },
    );
  }

  // ── Empty states — `B2 · 1d` ────────────────────────────────────────────────

  Widget _buildEmptyOrFiltered(
    BuildContext context,
    List<TaskItem> queue,
    TaskListState listState,
    AppLocalizations l10n,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (queue.isEmpty) {
      // The screen a user lands on while waiting for something, so its empty
      // state carries the way back to where work is started.
      return _EmptyBlock(
        icon: Icons.checklist_rounded,
        title: l10n.noTasksInQueue,
        titleStyle: textTheme.titleLarge,
        description: l10n.submitTaskFromWorkbench,
        action: AppButton(
          label: l10n.goToWorkbench,
          onPressed: () => Provider.of<AppState>(context, listen: false)
              .navigateToScreen(AppDestination.workbench.index),
        ),
        iconColor: scheme.outline,
      );
    }

    // Empty because of the filter, not the queue: the counts above keep their
    // figures, and the one action puts the filter back.
    final title = switch (listState.filter) {
      TaskFilter.running => l10n.noRunningTasks,
      TaskFilter.pending => l10n.noPendingTasks,
      TaskFilter.done => l10n.noCompletedTasks,
      TaskFilter.failed => l10n.noFailedTasks,
      TaskFilter.all => l10n.noTasksInQueue,
    };
    return _EmptyBlock(
      icon: Icons.filter_alt_off_outlined,
      title: title,
      titleStyle: textTheme.titleMedium,
      description: l10n.filteredEmptyHint(queue.length),
      action: AppButton(
        label: l10n.viewAllTasks,
        variant: AppButtonVariant.secondary,
        accentLabel: true,
        onPressed: () => listState.setFilter(TaskFilter.all),
      ),
      iconColor: scheme.outline,
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _handleBulkAction(String action, TaskQueueService queue) async {
    if (action == 'clear_completed') {
      final toRemove = queue.queue
          .where((t) =>
              t.status == TaskStatus.completed ||
              t.status == TaskStatus.failed ||
              t.status == TaskStatus.cancelled)
          .map((t) => t.id)
          .toList();
      for (final id in toRemove) {
        queue.removeTask(id);
      }
    } else if (action == 'cancel_pending') {
      final toCancel =
          queue.queue.where((t) => t.status == TaskStatus.pending).map((t) => t.id).toList();
      for (final id in toCancel) {
        queue.cancelTask(id);
      }
    } else if (action == 'clear_all') {
      // Waiting tasks are cancelled first and cleared with the finished ones.
      // A running task is left alone: cancelling it mid-write would let its
      // executor save the row back after the clear deleted it.
      final waiting =
          queue.queue.where((t) => t.status == TaskStatus.pending).map((t) => t.id).toList();
      for (final id in waiting) {
        await queue.cancelTask(id);
      }
      final toRemove = queue.queue
          .where((t) =>
              t.status == TaskStatus.completed ||
              t.status == TaskStatus.failed ||
              t.status == TaskStatus.cancelled)
          .map((t) => t.id)
          .toList();
      for (final id in toRemove) {
        await queue.removeTask(id);
      }
    }
  }

  /// `B2 · 1b` 清除全部确认: 440 wide, the error plate, and the solid error fill
  /// on the confirm. Cancel takes focus, so Enter is never the key that
  /// clears.
  Future<void> _confirmClearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final queue = Provider.of<AppState>(context, listen: false).taskQueue;
    final running = queue.queue.where((t) => t.status == TaskStatus.processing).length;

    final confirmed = await AppDialog.show<bool>(
      context,
      maxWidth: 440,
      icon: Icons.delete_sweep_outlined,
      iconColor: scheme.error,
      title: l10n.clearAllTasksTitle,
      subtitle: running > 0 ? l10n.clearAllRunningNote(running) : null,
      content: Text(
        l10n.clearAllKeepsFiles,
        style: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: AppType.proseHeight,
        ),
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: l10n.clearAll,
          variant: AppButtonVariant.destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (!mounted || confirmed != true) return;
    _handleBulkAction('clear_all', queue);
  }
}

// ════════════════════════════════════════════════════════════════════════════
/// One labelled line of a task's detail.
///
/// Its own widget so the layout can be pinned without standing up the screen's
/// AppState and database — both properties below shipped wrong and neither is
/// visible from reading a call site.
class TaskInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Lines a value may occupy before it is ellipsized. A prompt is the only
  /// value long enough to reach this; the whole text stays available from the
  /// card's menu (copy prompt).
  static const int maxValueLines = 4;

  const TaskInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        // A value can run to several lines, and centering parks the icon and
        // label halfway down it — which reads as if the lines above the label
        // belonged to the row before.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sits on the first line of text rather than the row's top edge.
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: AppSize.iconSm, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text('$label: ', style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodySmall,
              // maxLines is what makes the ellipsis do anything: unbounded, the
              // overflow setting is inert and the text just keeps wrapping.
              maxLines: maxValueLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
