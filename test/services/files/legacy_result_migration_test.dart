import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/files/directory_access_service.dart';
import 'package:joycai_image_ai_toolkits/services/files/legacy_result_migration.dart';
import 'package:joycai_image_ai_toolkits/services/files/persistent_media_service.dart';
import 'package:path/path.dart' as p;

import '../../support/in_memory_database.dart';

void main() {
  late Directory root;
  late Directory legacy;
  late DatabaseService database;
  late PersistentMediaService storage;
  late LegacyResultMigration migration;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy-results-');
    legacy = await Directory(p.join(root.path, 'old')).create();
    database = await openTestDatabase();
    storage = PersistentMediaService(dataDirectory: () async => p.join(root.path, 'private'));
    migration = LegacyResultMigration(
      database: database,
      storage: storage,
      access: DirectoryAccessService(useNative: false),
    );
    await database.saveSetting('result_cache_directory', legacy.path);
  });
  tearDown(() async {
    await closeTestDatabase(database);
    await root.delete(recursive: true);
  });

  test('copies sidecars and rewrites full history without changing remote jobs or prose', () async {
    final image = await File(p.join(legacy.path, 'result.png')).writeAsString('image');
    final text = await File(p.join(legacy.path, 'result.txt')).writeAsString('prompt');
    final db = await database.database;
    await db.insert('tasks', {
      'id': 'remote',
      'status': 'pending',
      'operation_name': 'paid-job',
      'result_path': jsonEncode([image.path]),
      'image_path': jsonEncode([image.path]),
      'parameters': jsonEncode({
        'generation': {
          'media': [
            {'path': image.path},
          ],
        },
        'prompt': image.path,
      }),
      'batch_state': jsonEncode({'outputDir': legacy.path, 'requestId': 'paid-batch'}),
    });
    await db.insert('assistant_sessions', {
      'id': 'session',
      'ref_images': jsonEncode([image.path]),
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('assistant_messages', {
      'session_id': 'session',
      'seq': 0,
      'created_at': 1,
      'message': jsonEncode({
        'images': [image.path],
        'content': 'look at ${image.path}',
      }),
    });
    await db.insert('image_layers', {
      'path': image.path,
      'set_id': 'set',
      'z_index': 1,
      'created_at': '2026-11-04',
    });
    await database.saveSetting('output_directory', legacy.path);
    expect(await migration.run(), 2);
    final row = (await db.query('tasks')).single;
    final copied = (jsonDecode(row['result_path'] as String) as List).single as String;
    expect(await File(copied).readAsString(), 'image');
    expect(await File(p.setExtension(copied, '.txt')).readAsString(), 'prompt');
    expect(row['operation_name'], 'paid-job');
    expect(row['status'], 'pending');
    expect(jsonDecode(row['parameters'] as String)['prompt'], image.path);
    expect(jsonDecode(row['batch_state'] as String)['requestId'], 'paid-batch');
    expect((await db.query('image_layers')).single['path'], copied);
    final message = jsonDecode((await db.query('assistant_messages')).single['message'] as String);
    expect(message['images'], [copied]);
    expect(message['content'], 'look at ${image.path}');
    expect(jsonDecode((await db.query('assistant_sessions')).single['ref_images'] as String), [
      copied,
    ]);
    expect(await image.exists(), isTrue);
    expect(await text.exists(), isTrue);
    expect(await database.getSetting('legacy_result_cache_directory'), isNull);
    expect(await database.getSetting('output_directory'), (await storage.resultsDirectory()).path);
    expect(await migration.run(), 0);
  });

  test('completed copy before DB commit is reused after restart', () async {
    final file = await File(p.join(legacy.path, 'paid.mp4')).writeAsString('video');
    final copied = await storage.migrateResult(file.path);
    expect(await migration.run(), 1);
    expect((await (await storage.resultsDirectory()).list().toList()).length, 1);
    expect(await File(copied).readAsString(), 'video');
  });

  test('copy conflict keeps history and source settings intact, then permits retry', () async {
    final file = await File(p.join(legacy.path, 'paid.png')).writeAsString('original');
    final copied = await storage.migrateResult(file.path);
    await File(copied).writeAsString('different');
    final db = await database.database;
    await db.insert('tasks', {
      'id': 'old',
      'result_path': jsonEncode([file.path]),
    });
    await expectLater(migration.run(), throwsA(isA<FileSystemException>()));
    expect(await database.getSetting('result_cache_directory'), legacy.path);
    expect((await db.query('tasks')).single['result_path'], jsonEncode([file.path]));
    expect(await File(copied).readAsString(), 'different');
    await File(copied).delete();
    expect(await migration.run(), 1);
  });

  test('database failure rolls all references back and retry reuses copies', () async {
    final file = await File(p.join(legacy.path, 'paid.png')).writeAsString('result');
    final db = await database.database;
    await db.insert('tasks', {
      'id': 'history',
      'result_path': jsonEncode([file.path]),
    });
    await db.execute(
      'CREATE TRIGGER reject_migration BEFORE INSERT ON settings '
      "WHEN NEW.key = 'result_cache_directory' BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(migration.run(), throwsA(anything));
    expect((await db.query('tasks')).single['result_path'], jsonEncode([file.path]));
    expect(await database.getSetting('result_cache_directory'), legacy.path);
    await db.execute('DROP TRIGGER reject_migration');
    expect(await migration.run(), 1);
    expect((await (await storage.resultsDirectory()).list().toList()).length, 1);
  });

  test('missing roots and symlinks do not retire legacy settings', () async {
    await legacy.delete();
    await expectLater(migration.run(), throwsA(isA<FileSystemException>()));
    await legacy.create();
    final outside = await File(p.join(root.path, 'outside.png')).writeAsString('outside');
    await Link(p.join(legacy.path, 'linked.png')).create(outside.path);
    await expectLater(migration.run(), throwsA(isA<FileSystemException>()));
    expect(await database.getSetting('result_cache_directory'), legacy.path);
    expect(await outside.readAsString(), 'outside');
  });

  test('nested same names stay distinct and incomplete writes are excluded', () async {
    for (final folder in ['one', 'two']) {
      final dir = await Directory(p.join(legacy.path, folder)).create();
      await File(p.join(dir.path, 'image.png')).writeAsString(folder);
    }
    await File(p.join(legacy.path, 'unfinished.partial')).writeAsString('incomplete');
    expect(await migration.run(), 2);
    final files = await (await storage.resultsDirectory()).list().toList();
    expect(files.length, 2);
    expect(
      await Future.wait(files.cast<File>().map((file) => file.readAsString())),
      unorderedEquals(['one', 'two']),
    );
  });

  test('refuses a source containing the destination', () async {
    await database.saveSetting('result_cache_directory', root.path);
    await expectLater(migration.run(), throwsA(isA<FileSystemException>()));
    expect(await database.getSetting('result_cache_directory'), root.path);
  });
}
