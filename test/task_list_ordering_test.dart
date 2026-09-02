// `C1 11a`/`11b`: the task list has one sort key — creation time — and the
// pinned group is a switch laid over it, not a second key.
//
// These pin down the three complaints the old status-first sort produced: a
// just-finished task sitting below an older waiting one, a retried task
// jumping to the top, and an order that changed between a session and the
// next launch.
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/task_list_ordering.dart';

void main() {
  final DateTime t0 = DateTime(2026, 9, 2, 13, 0);

  TaskItem task(String id, TaskStatus status, int minute, {DateTime? started}) =>
      TaskItem(
        id: id,
        imagePaths: const <String>[],
        modelId: 'm',
        parameters: const <String, dynamic>{},
        status: status,
        createdAt: t0.add(Duration(minutes: minute)),
        startTime: started,
      );

  List<String> ids(Iterable<TaskItem> tasks) => tasks.map((t) => t.id).toList();

  // Submission order, which is what the queue holds. Creation times are
  // deliberately *not* in status order.
  final List<TaskItem> queue = <TaskItem>[
    task('done-old', TaskStatus.completed, 0),
    task('pending-old', TaskStatus.pending, 5),
    task('failed', TaskStatus.failed, 10),
    task('done-new', TaskStatus.completed, 15),
    task('running', TaskStatus.processing, 20),
    task('cancelled', TaskStatus.cancelled, 25),
    task('pending-new', TaskStatus.pending, 30),
  ];

  group('creation time is the only key', () {
    test('newest first, pinning off, is one run regardless of status', () {
      final arranged = arrangeTasks(
        queue,
        filter: TaskFilter.all,
        order: TaskSortOrder.newestFirst,
        pinActive: false,
      );
      expect(arranged.pinned, isEmpty);
      expect(arranged.hasDivider, isFalse);
      expect(ids(arranged.rest), <String>[
        'pending-new',
        'cancelled',
        'running',
        'done-new',
        'failed',
        'pending-old',
        'done-old',
      ]);
    });

    test('oldest first is the exact reverse', () {
      final newest = arrangeTasks(
        queue,
        filter: TaskFilter.all,
        order: TaskSortOrder.newestFirst,
        pinActive: false,
      );
      final oldest = arrangeTasks(
        queue,
        filter: TaskFilter.all,
        order: TaskSortOrder.oldestFirst,
        pinActive: false,
      );
      expect(ids(oldest.rest), ids(newest.rest).reversed.toList());
    });

    test('a just-finished task is not pushed under an older waiting one', () {
      // The old sort put every pending task above every completed one, so
      // done-new (13:15) sat below pending-old (13:05).
      final arranged = arrangeTasks(
        queue,
        filter: TaskFilter.all,
        order: TaskSortOrder.newestFirst,
        pinActive: false,
      );
      final list = ids(arranged.rest);
      expect(list.indexOf('done-new'), lessThan(list.indexOf('pending-old')));
    });

    test('start time plays no part', () {
      // A retry clears and later rewrites startTime. Give the oldest task the
      // newest start and it must stay where its creation time puts it.
      final retried = <TaskItem>[
        task('a', TaskStatus.completed, 0, started: t0.add(const Duration(hours: 2))),
        task('b', TaskStatus.completed, 1, started: t0),
      ];
      final arranged = arrangeTasks(
        retried,
        filter: TaskFilter.all,
        order: TaskSortOrder.newestFirst,
        pinActive: false,
      );
      expect(ids(arranged.rest), <String>['b', 'a']);
    });
  });

  group('pinning', () {
    test('lifts running and pending above the seam, each side by creation time', () {
      final arranged = arrangeTasks(
        queue,
        filter: TaskFilter.all,
        order: TaskSortOrder.newestFirst,
        pinActive: true,
      );
      expect(ids(arranged.pinned), <String>['pending-new', 'running', 'pending-old']);
      expect(ids(arranged.rest), <String>['cancelled', 'done-new', 'failed', 'done-old']);
      expect(arranged.hasDivider, isTrue);
    });

    test('follows the sort direction inside the pinned group too', () {
      final arranged = arrangeTasks(
        queue,
        filter: TaskFilter.all,
        order: TaskSortOrder.oldestFirst,
        pinActive: true,
      );
      expect(ids(arranged.pinned), <String>['pending-old', 'running', 'pending-new']);
    });

    test('draws no seam when one side is empty', () {
      final history = queue.where((t) => !isActiveTask(t)).toList();
      final arranged = arrangeTasks(
        history,
        filter: TaskFilter.all,
        order: TaskSortOrder.newestFirst,
        pinActive: true,
      );
      expect(arranged.pinned, isEmpty);
      expect(arranged.hasDivider, isFalse);
      expect(arranged.length, history.length);
    });
  });

  group('filtering', () {
    test('failed includes cancelled — one pill, per 11a note 04', () {
      final arranged = arrangeTasks(
        queue,
        filter: TaskFilter.failed,
        order: TaskSortOrder.newestFirst,
        pinActive: true,
      );
      expect(ids(arranged.rest), <String>['cancelled', 'failed']);
      expect(arranged.hasDivider, isFalse);
    });

    test('a single-status filter never produces a seam', () {
      for (final filter in <TaskFilter>[TaskFilter.running, TaskFilter.pending, TaskFilter.done]) {
        final arranged = arrangeTasks(
          queue,
          filter: filter,
          order: TaskSortOrder.newestFirst,
          pinActive: true,
        );
        expect(arranged.hasDivider, isFalse, reason: '$filter');
        expect(arranged.isEmpty, isFalse, reason: '$filter');
      }
    });

    test('an empty result is empty, not a divider', () {
      final arranged = arrangeTasks(
        queue.where((t) => t.status == TaskStatus.completed).toList(),
        filter: TaskFilter.failed,
        order: TaskSortOrder.newestFirst,
        pinActive: true,
      );
      expect(arranged.isEmpty, isTrue);
      expect(arranged.length, 0);
    });
  });

  group('ties', () {
    test('tasks created in the same instant keep submission order, in the sort direction', () {
      // A batch submit stamps several tasks with one clock reading. Dart's
      // sort is not stable, so this is the case the explicit index exists for.
      final batch = <TaskItem>[
        for (int i = 0; i < 6; i++) task('b$i', TaskStatus.completed, 0),
      ];
      final newest = arrangeTasks(
        batch,
        filter: TaskFilter.all,
        order: TaskSortOrder.newestFirst,
        pinActive: false,
      );
      final oldest = arrangeTasks(
        batch,
        filter: TaskFilter.all,
        order: TaskSortOrder.oldestFirst,
        pinActive: false,
      );
      expect(ids(oldest.rest), <String>['b0', 'b1', 'b2', 'b3', 'b4', 'b5']);
      expect(ids(newest.rest), <String>['b5', 'b4', 'b3', 'b2', 'b1', 'b0']);
    });

    test('the same input arranges the same way every time', () {
      final first = ids(arrangeTasks(queue,
              filter: TaskFilter.all, order: TaskSortOrder.newestFirst, pinActive: true)
          .rest);
      for (int i = 0; i < 5; i++) {
        final again = ids(arrangeTasks(queue,
                filter: TaskFilter.all, order: TaskSortOrder.newestFirst, pinActive: true)
            .rest);
        expect(again, first);
      }
    });
  });
}
