import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// `TaskQueueService.removeTask` and the row behind each task.
///
/// The bug this pins: the in-memory removal was guarded by status, the
/// database delete was not. Removing a waiting or running task — which the
/// task queue's Clear All does for every task that is not running — left the
/// task in the queue and deleted its row, so it disappeared on the next launch.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_remove_task_test');

  TaskItem task(String id, TaskStatus status) => TaskItem(
        id: id,
        imagePaths: const <String>[],
        modelId: 'test-model',
        parameters: const <String, dynamic>{'prompt': 'p'},
        status: status,
      );

  Future<Set<String>> storedIds() async =>
      (await DatabaseService().getRecentTasks(50)).map((row) => row['id'] as String).toSet();

  /// A service whose queue holds [tasks], loaded the way the app loads them:
  /// rows first, then the service reads them back on construction.
  ///
  /// The rows are stored finished so the load never starts executing one; the
  /// statuses under test are set on the loaded items afterwards.
  Future<TaskQueueService> serviceWith(Map<String, TaskStatus> tasks) async {
    for (final id in tasks.keys) {
      await DatabaseService().saveTask(task(id, TaskStatus.completed).toMap());
    }
    final service = TaskQueueService();
    for (var i = 0; i < 100 && !tasks.keys.every((id) => service.queue.any((t) => t.id == id)); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (final item in service.queue) {
      final status = tasks[item.id];
      if (status != null) item.status = status;
    }
    return service;
  }

  test('a waiting task keeps both its place in the queue and its row', () async {
    final service = await serviceWith({'waiting-1': TaskStatus.pending});

    await service.removeTask('waiting-1');

    expect(service.queue.any((t) => t.id == 'waiting-1'), isTrue);
    expect(await storedIds(), contains('waiting-1'),
        reason: 'the row was deleted while the task stayed queued');
  });

  test('a running task keeps both its place in the queue and its row', () async {
    final service = await serviceWith({'running-1': TaskStatus.processing});

    await service.removeTask('running-1');

    expect(service.queue.any((t) => t.id == 'running-1'), isTrue);
    expect(await storedIds(), contains('running-1'));
  });

  test('a finished task leaves the queue and loses its row', () async {
    final service = await serviceWith({
      'done-1': TaskStatus.completed,
      'failed-1': TaskStatus.failed,
      'cancelled-1': TaskStatus.cancelled,
    });

    for (final id in const ['done-1', 'failed-1', 'cancelled-1']) {
      await service.removeTask(id);
      expect(service.queue.any((t) => t.id == id), isFalse, reason: id);
      expect(await storedIds(), isNot(contains(id)), reason: id);
    }
  });
}
