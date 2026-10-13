import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/mcp_request_repository.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/task_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  test('v50 upgrades old tasks without losing outputs and is repeatable', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE tasks(id TEXT PRIMARY KEY, status TEXT, type TEXT, operation_name TEXT)',
    );
    await DatabaseMigration.migrate(db, 49, 50);
    await DatabaseMigration.migrate(db, 49, 50);
    final columns = await db.rawQuery('PRAGMA table_info(tasks)');
    expect(columns.map((c) => c['name']), containsAll(['task_error', 'warnings']));
    expect(await db.query('mcp_requests'), isEmpty);
  });

  test(
    'acceptance is atomic, replay keys outlive history, interruption keeps partial output',
    () async {
      final db = await openTestDatabase();
      addTearDown(() => closeTestDatabase(db));
      final requests = McpRequestRepository(db: db);
      final tasks = TaskRepository(db: db);
      final task = TaskItem(
        id: 'one',
        modelId: 'image',
        imagePaths: [],
        status: TaskStatus.processing,
        resultPaths: ['/saved.png'],
        parameters: {'origin': 'mcp'},
        warnings: ['A partial failure'],
      );
      await requests.insert('key', 'digest', task);
      final second = TaskItem(id: 'two', modelId: 'image', imagePaths: [], parameters: {});
      await expectLater(
        requests.insert('key', 'different', second),
        throwsA(isA<DatabaseException>()),
      );
      expect(await tasks.getTask('two'), null);
      await tasks.cleanupStuckTasks();
      final recovered = (await tasks.getTask('one'))!;
      expect(recovered.status, TaskStatus.failed);
      expect(recovered.error!['code'], 'interrupted');
      expect(recovered.resultPaths, ['/saved.png']);
      expect(recovered.warnings, ['A partial failure']);
      await tasks.deleteTask('one');
      expect((await requests.find('key'))!['task_id'], 'one');
    },
  );
}
