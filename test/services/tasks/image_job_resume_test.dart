import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/task_repository.dart';
import 'package:joycai_image_ai_toolkits/services/llm/image_job.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  test('restart requeues saved image job and preserves recovery data', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));
    const job = ImageJob(
      id: 'accepted',
      base: 'https://example.test/api/v1',
      model: 'wan2.7-image',
      inputImages: 2,
      sentSize: '1000*1000',
    );
    final task = TaskItem(
      id: 'image-resume',
      type: TaskType.imageProcess,
      imagePaths: ['missing.png'],
      modelId: 'wan2.7-image',
      parameters: {ImageJob.taskKey: job.toJson()},
      status: TaskStatus.processing,
      operationName: job.id,
      operationSurface: ImageJob.surface,
    );
    await db.saveTask(task);
    final repository = TaskRepository(db: db);
    await repository.cleanupStuckTasks();
    final restored = (await repository.getRecentTasks(20)).single;
    expect(restored.status, TaskStatus.pending);
    expect(ImageJob.fromJson(restored.parameters[ImageJob.taskKey])!.inputImages, 2);
    restored.status = TaskStatus.failed;
    expect(TaskQueueService.canResumeVideoJob(restored), isTrue);
    restored.status = TaskStatus.cancelled;
    expect(TaskQueueService.canResumeVideoJob(restored), isTrue);
    restored.parameters.remove(ImageJob.taskKey);
    expect(TaskQueueService.canResumeVideoJob(restored), isFalse);
  });
}
