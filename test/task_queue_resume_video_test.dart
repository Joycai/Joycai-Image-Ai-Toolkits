import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// A video task whose job was accepted (and billed) can pick that job back
/// up — poll again, download again — instead of paying for a new one. A
/// plain retry still starts over, on purpose.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_resume_video_test');

  TaskItem video(String id, {String? operation, TaskStatus status = TaskStatus.failed}) =>
      TaskItem(
        id: id,
        imagePaths: const <String>[],
        modelId: 'veo-test',
        parameters: const <String, dynamic>{'prompt': 'p'},
        type: TaskType.videoGenerate,
        status: status,
      )
        ..operationName = operation
        ..operationSurface = operation == null ? null : 'test-surface';

  group('canResumeVideoJob', () {
    test('a failed or cancelled video with a job id can', () {
      expect(TaskQueueService.canResumeVideoJob(video('a', operation: 'op/1')), isTrue);
      expect(
          TaskQueueService.canResumeVideoJob(
              video('b', operation: 'op/1', status: TaskStatus.cancelled)),
          isTrue);
    });

    test('no job id, a running task or another task type cannot', () {
      expect(TaskQueueService.canResumeVideoJob(video('c')), isFalse);
      expect(
          TaskQueueService.canResumeVideoJob(
              video('d', operation: 'op/1', status: TaskStatus.processing)),
          isFalse);
      final image = TaskItem(
        id: 'e',
        imagePaths: const <String>[],
        modelId: 'm',
        parameters: const <String, dynamic>{},
        status: TaskStatus.failed,
      )..operationName = 'op/1';
      expect(TaskQueueService.canResumeVideoJob(image), isFalse);
    });
  });

  Future<(TaskQueueService, TaskItem)> queued(String id) async {
    await DatabaseService()
        .saveTask(video(id, operation: 'op/$id', status: TaskStatus.completed));
    final service = TaskQueueService()..updateConcurrency(0);
    for (var i = 0; i < 100 && !service.queue.any((t) => t.id == id); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final task = service.queue.firstWhere((t) => t.id == id)..status = TaskStatus.failed;
    return (service, task);
  }

  test('resuming keeps the job; retrying forgets it', () async {
    final (service, resumed) = await queued('resume-1');
    await service.resumeVideoJob('resume-1');
    expect(resumed.status, TaskStatus.pending);
    expect(resumed.operationName, 'op/resume-1');
    expect(resumed.operationSurface, 'test-surface');

    final (other, retried) = await queued('retry-1');
    await other.retryTask('retry-1');
    expect(retried.status, TaskStatus.pending);
    expect(retried.operationName, isNull);
  });
}
