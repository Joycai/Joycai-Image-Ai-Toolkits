import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/task_repository.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// B3: a submitted video job is billed whether or not anyone polls it. Its id
/// is persisted at submit, an interrupted run resumes polling that id instead
/// of being written off, and only an explicit user retry submits afresh
/// (standards 13 §4.3, 14 §1).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  usePrivateDataDir('joycai_video_job_resume_test');

  TaskItem task(
    String id, {
    TaskType type = TaskType.videoGenerate,
    TaskStatus status = TaskStatus.processing,
    String? operationName,
  }) =>
      TaskItem(
        id: id,
        type: type,
        imagePaths: const [],
        modelId: 'm',
        parameters: const {},
        status: status,
        operationName: operationName,
        operationSurface: operationName == null ? null : 'openai-videos',
      );

  test('operation_name round-trips through the row', () {
    final restored =
        TaskItem.fromMap(task('t', operationName: 'video_abc').toMap());
    expect(restored.operationName, 'video_abc');
    expect(restored.operationSurface, 'openai-videos');
  });

  test('an interrupted video task with a job id is requeued, not failed',
      () async {
    final db = DatabaseService();
    await db.saveTask(task('video-resume', operationName: 'video_abc'));
    await db.saveTask(task('video-unsubmitted'));
    await db.saveTask(task('image-running', type: TaskType.imageProcess));

    await TaskRepository().cleanupStuckTasks();

    final rows = {
      for (final task in await TaskRepository().getRecentTasks(200)) task.id: task,
    };
    expect(rows['video-resume']!.status, TaskStatus.pending);
    expect(rows['video-resume']!.operationName, 'video_abc');
    // Nothing was accepted upstream for these, so there is nothing to resume.
    expect(rows['video-unsubmitted']!.status, TaskStatus.failed);
    expect(rows['image-running']!.status, TaskStatus.failed);

    for (final id in rows.keys) {
      await db.deleteTask(id);
    }
  });

  test('a user retry forgets the job id and submits afresh', () async {
    await DatabaseService().saveTask(task(
      'video-retry',
      status: TaskStatus.failed,
      operationName: 'video_old',
    ));

    final queue = TaskQueueService();
    addTearDown(queue.dispose);
    await queue.resumePendingTasks();
    await queue.retryTask('video-retry');

    final retried = queue.queue.firstWhere((t) => t.id == 'video-retry');
    expect(retried.operationName, isNull);
    expect(retried.operationSurface, isNull);
    expect(retried.logs.any((l) => l.contains('video_old')), isTrue);
  });
}
