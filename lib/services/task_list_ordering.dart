import '../models/task_item.dart';

/// Which subset of the queue the task list shows.
///
/// [failed] covers cancelled tasks too. `C1 11a` (note 04) weighed splitting
/// them and decided against it: both are terminal, both take the same two
/// actions (retry / remove), a cancellation is something the user did
/// themselves and so already knows about, and a sixth pill is what would put
/// the phone's filter strip back over its width. A cancelled row tells itself
/// apart by its grey stripe, its glyph and its 「已取消 · 手动」 line instead.
enum TaskFilter { all, running, pending, done, failed }

extension TaskFilterMatch on TaskFilter {
  bool matches(TaskItem task) => switch (this) {
        TaskFilter.all => true,
        TaskFilter.running => task.status == TaskStatus.processing,
        TaskFilter.pending => task.status == TaskStatus.pending,
        TaskFilter.done => task.status == TaskStatus.completed,
        TaskFilter.failed =>
          task.status == TaskStatus.failed || task.status == TaskStatus.cancelled,
      };
}

/// Which way the list runs along its one sort key, [TaskItem.createdAt].
enum TaskSortOrder { newestFirst, oldestFirst }

/// A task that is still going to do something: running, or waiting to run.
bool isActiveTask(TaskItem task) =>
    task.status == TaskStatus.pending || task.status == TaskStatus.processing;

/// The list as the screen draws it: the tasks pinned above the seam, and the
/// tasks below it. With pinning off everything is in [rest].
class ArrangedTasks {
  final List<TaskItem> pinned;
  final List<TaskItem> rest;

  const ArrangedTasks({required this.pinned, required this.rest});

  static const ArrangedTasks empty = ArrangedTasks(pinned: [], rest: []);

  bool get isEmpty => pinned.isEmpty && rest.isEmpty;
  int get length => pinned.length + rest.length;

  /// Whether there is a seam to draw — only when both sides have something on
  /// them. A list that is all history, or all queue, is one run.
  bool get hasDivider => pinned.isNotEmpty && rest.isNotEmpty;
}

/// Filters [queue] and orders what is left by creation time.
///
/// This replaces a sort that grouped by status first (running, then pending,
/// then everything else) and only then by age — which read as no order at
/// all: a task that had just finished sat *below* a waiting one created an
/// hour earlier, and a retried task moved to the top on the next launch
/// because the group order was really `start_time` order underneath.
///
/// Now the only key is [TaskItem.createdAt]. Pinning the active tasks is a
/// switch laid *on top of* that order (`C1 11a` note 03): within the pinned
/// group the same key applies, so a re-queued task keeps its place among the
/// tasks it was created between rather than jumping ahead of them.
///
/// Ties — two tasks created in the same millisecond, which a batch submit
/// can do — fall back to queue (submission) order, run in the same direction
/// as the sort, so the result is the same on every rebuild. Dart's `sort` is
/// not stable, which is why the index is carried explicitly.
ArrangedTasks arrangeTasks(
  List<TaskItem> queue, {
  required TaskFilter filter,
  required TaskSortOrder order,
  required bool pinActive,
}) {
  final indexed = <(int, TaskItem)>[
    for (final (index, task) in queue.indexed)
      if (filter.matches(task)) (index, task),
  ];

  final direction = order == TaskSortOrder.newestFirst ? -1 : 1;
  indexed.sort((a, b) {
    final byTime = a.$2.createdAt.compareTo(b.$2.createdAt);
    if (byTime != 0) return byTime * direction;
    return a.$1.compareTo(b.$1) * direction;
  });

  final sorted = [for (final entry in indexed) entry.$2];
  if (!pinActive) return ArrangedTasks(pinned: const [], rest: sorted);
  return ArrangedTasks(
    pinned: sorted.where(isActiveTask).toList(),
    rest: sorted.where((task) => !isActiveTask(task)).toList(),
  );
}
