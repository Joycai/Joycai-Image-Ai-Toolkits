import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/files/persistent_media_service.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late DatabaseService db;
  late PersistentMediaService media;
  late TaskQueueService queue;
  Future<TaskQueueService> createQueue() async {
    final queue = TaskQueueService(database: db, mediaStorage: media, preserveTaskInputs: true);
    queue.updateConcurrency(0);
    await queue.ready;
    return queue;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('queue-media-test-');
    db = await openTestDatabase();
    media = PersistentMediaService(dataDirectory: () async => p.join(root.path, 'private'));
    queue = await createQueue();
  });
  tearDown(() async {
    queue.dispose();
    await closeTestDatabase(db);
    await root.delete(recursive: true);
  });

  test('durable acceptance survives deletion of source and queue recreation', () async {
    final source = await File(p.join(root.path, 'source.png')).writeAsString('pixels');
    await queue.addTask([source.path], 'model', {}, id: 'accepted');
    final savedPath = queue.queue.single.imagePaths.single;
    expect(savedPath, isNot(source.path));
    await source.delete();
    queue.dispose();
    queue = await createQueue();
    expect(queue.queue.single.status, TaskStatus.pending);
    expect(queue.queue.single.imagePaths.single, savedPath);
    expect(await File(savedPath).readAsString(), 'pixels');
  });

  test('missing input is never persisted or published as a queued task', () async {
    await expectLater(
      queue.addTask([p.join(root.path, 'missing.png')], 'model', {}),
      throwsA(isA<FileSystemException>()),
    );
    expect(queue.queue, isEmpty);
    expect(await db.getRecentTasks(20), isEmpty);
  });

  test('old missing queued input fails locally while a remote job retains its id', () async {
    for (final remote in [false, true]) {
      await db.saveTask(
        TaskItem(
          id: remote ? 'remote' : 'local',
          type: TaskType.videoGenerate,
          imagePaths: [p.join(root.path, 'missing.png')],
          modelId: 'model',
          parameters: {},
          operationName: remote ? 'already-paid' : null,
        ),
      );
    }
    queue.dispose();
    queue = await createQueue();
    expect(queue.queue.firstWhere((task) => task.id == 'local').status, TaskStatus.failed);
    final remote = queue.queue.firstWhere((task) => task.id == 'remote');
    expect(remote.status, TaskStatus.pending);
    expect(remote.operationName, 'already-paid');
  });
}
