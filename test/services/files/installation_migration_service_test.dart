import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_paths.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/files/installation_migration_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Directory old;
  late Directory support;
  late Database source;
  late InstallationMigrationService migration;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('installation-import-');
    old = await Directory(p.join(root.path, 'old')).create();
    support = await Directory(p.join(root.path, 'sandbox')).create();
    source = await databaseFactoryFfi.openDatabase(
      p.join(old.path, InstallationMigrationService.databaseName),
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: DatabaseService.dbVersion,
        onCreate: (db, _) => DatabaseMigration.onCreate(db),
      ),
    );
    migration = InstallationMigrationService(
      supportDirectory: () async => support.path,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await source.close();
    await root.delete(recursive: true);
  });

  Future<File> asset(String relative, String bytes) async {
    final file = File(p.joinAll([old.path, ...p.posix.split(relative)]));
    await file.parent.create(recursive: true);
    return file.writeAsString(bytes);
  }

  test('imports WAL snapshot, all history and owned files; retains occupied destination', () async {
    await source.rawQuery('PRAGMA journal_mode = WAL');
    await source.rawQuery('PRAGMA wal_autocheckpoint = 0');
    final image = await asset('media/results/a.png', 'image');
    await asset('usage-journal/event.json', '{"id":"event"}');
    await asset('fonts/custom.ttf', 'font');
    await asset('mcp-inputs/ref.png', 'ref');
    await asset('directory-grants.plist', 'must not import');
    final previous = await File(p.join(support.path, 'joycai_workbench.db'))
        .writeAsString('previous');
    await source.insert('tasks', {
      'id': 'remote',
      'status': 'pending',
      'operation_name': 'paid-operation',
      'image_path': jsonEncode([image.path]),
      'result_path': jsonEncode([image.path]),
      'parameters': jsonEncode({
        'prompt': image.path,
        'generation': {
          'media': [
            {'path': image.path},
          ],
        },
      }),
      'batch_state': jsonEncode({'requestId': 'paid-batch', 'outputDir': image.parent.path}),
    });
    await source.insert('assistant_sessions', {
      'id': 'session',
      'created_at': 1,
      'updated_at': 1,
      'ref_images': jsonEncode([image.path]),
    });
    await source.insert('assistant_messages', {
      'session_id': 'session',
      'seq': 0,
      'created_at': 1,
      'message': jsonEncode({
        'images': [image.path],
        'content': image.path,
      }),
    });
    await source.insert('image_layers', {
      'path': image.path,
      'set_id': 'layer',
      'z_index': 0,
      'created_at': 'now',
    });
    for (final entry in {
      'mcp_enabled': 'true',
      'mcp_token': 'secret',
      'ai_data_sharing_consent_v1': 'must-not-import',
      'mcp_roots': '[]',
      'output_directory': image.parent.path,
      'knowledge_base_path': '/external/kb',
      'proxy_password': 'password',
    }.entries) {
      await source.insert('settings', {'key': entry.key, 'value': entry.value});
    }
    expect(await File('${source.path}-wal').length(), greaterThan(0));
    final destination = await migration.importDirectory(old.path);
    expect(await AppPaths.resolveDataDirectory(support.path), destination);
    expect(await previous.readAsString(), 'previous');
    expect(await image.readAsString(), 'image');
    final db = await databaseFactoryFfi.openDatabase(p.join(destination, 'joycai_workbench.db'));
    try {
      final task = (await db.query('tasks')).single;
      final copied = p.join(destination, 'media', 'results', 'a.png');
      expect(task['status'], 'pending');
      expect(task['operation_name'], 'paid-operation');
      expect(jsonDecode(task['parameters'] as String)['prompt'], image.path);
      expect(jsonDecode(task['parameters'] as String)['generation']['media'][0]['path'], copied);
      expect(jsonDecode(task['batch_state'] as String)['requestId'], 'paid-batch');
      expect(jsonDecode(task['batch_state'] as String)['outputDir'], p.dirname(copied));
      expect((await db.query('image_layers')).single['path'], copied);
      expect((await db.query('assistant_sessions')).single['ref_images'], jsonEncode([copied]));
      final message = jsonDecode(
        (await db.query('assistant_messages')).single['message'] as String,
      );
      expect(message['images'], [copied]);
      expect(message['content'], image.path);
      final settings = {for (final row in await db.query('settings')) row['key']: row['value']};
      expect(settings['mcp_enabled'], 'false');
      expect(settings['mcp_token'], isNull);
      expect(settings['ai_data_sharing_consent_v1'], isNull);
      expect(settings['proxy_password'], 'password');
      expect(settings['knowledge_base_path'], '/external/kb');
      expect(await File(copied).readAsString(), 'image');
      expect(await File(p.join(destination, 'usage-journal/event.json')).exists(), isTrue);
      expect(await File(p.join(destination, 'fonts/custom.ttf')).exists(), isTrue);
      expect(await File(p.join(destination, 'directory-grants.plist')).exists(), isFalse);
      expect((await source.query('tasks')).single['result_path'], jsonEncode([image.path]));
      expect(
        (await source.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['mcp_enabled'],
        )).single['value'],
        'true',
      );
    } finally {
      await db.close();
    }
  });

  test('failure leaves prior pointer and data intact, then retry succeeds', () async {
    final first = await migration.importDirectory(old.path);
    final media = await Directory(p.join(old.path, 'media')).create();
    await Link(p.join(media.path, 'external')).create(root.path);
    await expectLater(
      migration.importDirectory(old.path),
      throwsA(isA<InstallationMigrationException>()),
    );
    expect(await migration.currentDirectory(), first);
    expect((await Directory(p.join(support.path, 'installations')).list().toList()).length, 1);
    await Link(p.join(media.path, 'external')).delete();
    final second = await migration.importDirectory(old.path);
    expect(second, isNot(first));
    expect(await File(p.join(first, 'joycai_workbench.db')).exists(), isTrue);
    expect(await migration.currentDirectory(), second);
    final receipt = jsonDecode(
      await File(p.join(second, 'installation-import.json')).readAsString(),
    );
    expect(receipt['previous'], first);
  });

  test('rejects newer databases without switching or modifying source', () async {
    await source.setVersion(DatabaseService.dbVersion + 1);
    await expectLater(
      migration.importDirectory(old.path),
      throwsA(
        isA<InstallationMigrationException>().having(
          (e) => e.reason,
          'reason',
          InstallationMigrationError.newerSchema,
        ),
      ),
    );
    expect(await migration.currentDirectory(), support.path);
    expect(await source.getVersion(), DatabaseService.dbVersion + 1);
  });

  test('rejects unrelated database, missing database and overlapping roots', () async {
    final unrelated = await Directory(p.join(root.path, 'unrelated')).create();
    final db = await databaseFactoryFfi.openDatabase(p.join(unrelated.path, 'joycai_workbench.db'));
    await db.execute('CREATE TABLE other (id INTEGER)');
    await db.close();
    await expectLater(
      migration.importDirectory(unrelated.path),
      throwsA(isA<InstallationMigrationException>()),
    );
    await expectLater(
      migration.importDirectory(support.path),
      throwsA(isA<InstallationMigrationException>()),
    );
    await expectLater(
      migration.importDirectory(root.path),
      throwsA(isA<InstallationMigrationException>()),
    );
    final empty = await Directory(p.join(root.path, 'empty')).create();
    await expectLater(
      migration.importDirectory(empty.path),
      throwsA(isA<InstallationMigrationException>()),
    );
    expect(await migration.currentDirectory(), support.path);
  });

  test('upgrades only isolated copy before activation', () async {
    await source.execute('DROP TABLE usage_events');
    await source.setVersion(51);
    final destination = await migration.importDirectory(old.path);
    final db = await databaseFactoryFfi.openDatabase(p.join(destination, 'joycai_workbench.db'));
    expect(await db.getVersion(), DatabaseService.dbVersion);
    expect(await db.query('usage_events'), isEmpty);
    await db.close();
    expect(await source.getVersion(), 51);
    expect(
      await source.rawQuery("SELECT name FROM sqlite_master WHERE name = 'usage_events'"),
      isEmpty,
    );
  });

  test('choice and next-launch request do not touch live database', () async {
    expect(await migration.shouldOffer(), isTrue);
    await migration.finishChoice();
    expect(await migration.shouldOffer(), isFalse);
    await migration.requestOnNextLaunch();
    expect(await migration.shouldOffer(), isTrue);
    await migration.finishChoice();
    expect(await migration.shouldOffer(), isFalse);
    expect(await File(p.join(support.path, 'joycai_workbench.db')).exists(), isFalse);
  });

  test('activation reader refuses traversal and missing installation', () async {
    final pointer = File(p.join(support.path, 'active-installation'));
    await pointer.writeAsString('../../old');
    await expectLater(migration.currentDirectory(), throwsFormatException);
    await pointer.writeAsString('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    await expectLater(migration.currentDirectory(), throwsA(isA<FileSystemException>()));
  });

  test('detects source SQLite writes during copying and leaves current data selected', () async {
    await source.rawQuery('PRAGMA journal_mode = WAL');
    final changing = InstallationMigrationService(
      supportDirectory: () async => support.path,
      factory: _OnCopyOpen(() async {
        await source.insert('settings', {'key': 'changed', 'value': 'after snapshot'});
      }),
    );
    await expectLater(
      changing.importDirectory(old.path),
      throwsA(
        isA<InstallationMigrationException>().having(
          (e) => e.reason,
          'reason',
          InstallationMigrationError.sourceChanged,
        ),
      ),
    );
    expect(await migration.currentDirectory(), support.path);
    expect((await source.query('settings')).single['value'], 'after snapshot');
  });

  test('detects new media during copying and preserves missing references', () async {
    final changing = InstallationMigrationService(
      supportDirectory: () async => support.path,
      factory: _OnCopyOpen(() async {
        await asset('media/new.png', 'new');
      }),
    );
    await expectLater(
      changing.importDirectory(old.path),
      throwsA(
        isA<InstallationMigrationException>().having(
          (e) => e.reason,
          'reason',
          InstallationMigrationError.sourceChanged,
        ),
      ),
    );
    final missing = p.join(old.path, 'media/missing.png');
    await source.insert('tasks', {
      'id': 'missing',
      'image_path': jsonEncode([missing]),
    });
    final destination = await migration.importDirectory(old.path);
    final db = await databaseFactoryFfi.openDatabase(p.join(destination, 'joycai_workbench.db'));
    expect((await db.query('tasks')).single['image_path'], jsonEncode([missing]));
    await db.close();
  });
}

class _OnCopyOpen implements DatabaseFactory {
  _OnCopyOpen(this.onCopyOpen);
  final Future<void> Function() onCopyOpen;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) async {
    if (options?.onUpgrade != null) await onCopyOpen();
    return databaseFactoryFfi.openDatabase(path, options: options);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
