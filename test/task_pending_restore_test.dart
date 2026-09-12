import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/repositories/task_repository.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  usePrivateDataDir('joycai_pending_restore_test');

  test('recent task query always includes pending work', () async {
    for (var i = 0; i < 210; i++) {
      await DatabaseService().saveTask(
        TaskItem(
          id: 'done-$i',
          imagePaths: const [],
          modelId: 'm',
          parameters: const {},
          status: TaskStatus.completed,
          createdAt: DateTime(2026, 1, 2, 0, i),
        ).toMap(),
      );
    }
    await DatabaseService().saveTask(
      TaskItem(
        id: 'pending-old',
        imagePaths: const [],
        modelId: 'm',
        parameters: const {},
        status: TaskStatus.pending,
        createdAt: DateTime(2025, 1, 1),
      ).toMap(),
    );

    final rows = await TaskRepository().getRecentTasks(200);

    expect(rows.any((row) => row['id'] == 'pending-old'), isTrue);
    await DatabaseService().deleteTask('pending-old');
  });

  test('restored pending task is scheduled after loading', () async {
    final output = await Directory.systemTemp.createTemp(
      'joycai_pending_output',
    );
    addTearDown(() => output.delete(recursive: true));
    await DatabaseService().saveSetting('output_directory', output.path);
    await DatabaseService().saveTask(
      TaskItem(
        id: 'pending-download',
        type: TaskType.imageDownload,
        imagePaths: const [],
        modelId: 'm',
        parameters: const {'prefix': 'download'},
        status: TaskStatus.pending,
      ).toMap(),
    );

    final queue = TaskQueueService();
    addTearDown(queue.dispose);
    await queue.resumePendingTasks();
    TaskItem? loaded;
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (queue.queue.isNotEmpty) {
        loaded = queue.queue.firstWhere(
          (task) => task.id == 'pending-download',
        );
        if (loaded.status != TaskStatus.pending &&
            loaded.status != TaskStatus.processing) {
          break;
        }
      }
    }

    expect(loaded, isNotNull);
    expect(loaded!.status, TaskStatus.completed);
  });
}
