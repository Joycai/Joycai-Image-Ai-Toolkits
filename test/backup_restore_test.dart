import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers backup restore against a real (in-memory) schema.
///
/// `llm_models` references `llm_channels` and `fee_groups` without a cascade, so
/// these exercise the delete order under `PRAGMA foreign_keys = ON` as well as
/// what a restore must preserve rather than wipe.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  Future<Database> openTestDb() async {
    final db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseService.dbVersion,
        onCreate: (db, version) => DatabaseMigration.onCreate(db),
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    return db;
  }

  /// A channel + a model wired to it, mirroring a real user's setup.
  Future<int> seedChannelWithModel(Database db, {String apiKey = 'live-key'}) async {
    final channelId = await db.insert('llm_channels', {
      'display_name': 'My Gemini',
      'endpoint': 'https://generativelanguage.googleapis.com',
      'api_key': apiKey,
      'type': 'google-genai',
    });
    await db.insert('llm_models', {
      'model_id': 'gemini-3-pro',
      'model_name': 'Gemini 3 Pro',
      'type': 'image',
      'tag': 'General',
      'channel_id': channelId,
    });
    return channelId;
  }

  /// A backup as `getAllDataRaw` writes one: secrets redacted.
  Map<String, dynamic> backupFile({
    String channelName = 'My Gemini',
    String endpoint = 'https://generativelanguage.googleapis.com',
  }) {
    return {
      'export_type': 'full_backup',
      'schema_version': DatabaseService.dbVersion,
      'settings': [
        {'key': 'image_prefix', 'value': 'result'},
        {'key': 'output_directory', 'value': '/other/machine/out'},
        {'key': 'result_cache_directory', 'value': '/other/machine/cache'},
      ],
      'llm_channels': [
        {
          'id': 1,
          'display_name': channelName,
          'endpoint': endpoint,
          'api_key': '',
          'type': 'google-genai',
        },
      ],
      'llm_models': [
        {
          'id': 1,
          'model_id': 'gemini-3-pro',
          'model_name': 'Gemini 3 Pro',
          'type': 'image',
          'tag': 'General',
          'channel_id': 1,
        },
      ],
      'fee_groups': [],
      'downloader_cookies': [
        {'host': 'example.com', 'cookies': '', 'last_used': '2026-01-01'},
      ],
    };
  }

  group('restore', () {
    test('succeeds when models reference channels', () async {
      final db = await openTestDb();
      await seedChannelWithModel(db);

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, backupFile());
      });

      expect((await db.query('llm_models')).length, 1);
      expect((await db.query('llm_channels')).length, 1);
      await db.close();
    });

    test('keeps the API key when the backup redacted it', () async {
      final db = await openTestDb();
      await seedChannelWithModel(db, apiKey: 'live-key');

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, backupFile());
      });

      final channels = await db.query('llm_channels');
      expect(channels.single['api_key'], 'live-key');
      await db.close();
    });

    test('does not resurrect a key for a channel this machine never had', () async {
      final db = await openTestDb();
      await seedChannelWithModel(db, apiKey: 'live-key');

      await db.transaction((txn) async {
        await DatabaseService()
            .restoreBackupInto(txn, backupFile(channelName: 'Someone Else'));
      });

      final channels = await db.query('llm_channels');
      expect(channels.single['display_name'], 'Someone Else');
      expect(channels.single['api_key'], '');
      await db.close();
    });

    test('keeps local task history and cookies', () async {
      final db = await openTestDb();
      await seedChannelWithModel(db);
      await db.insert('tasks', {
        'id': 'task-1',
        'image_path': '/local/a.png',
        'status': 'completed',
        'type': 'imageProcess',
      });
      await db.insert('downloader_cookies', {
        'host': 'example.com',
        'cookies': 'session=abc',
        'last_used': '2026-07-01',
      });

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, backupFile());
      });

      expect((await db.query('tasks')).length, 1);
      final cookies = await db.query('downloader_cookies');
      expect(cookies.single['cookies'], 'session=abc');
      await db.close();
    });

    test('drops machine-specific paths when directories are excluded', () async {
      final db = await openTestDb();

      await db.transaction((txn) async {
        await DatabaseService()
            .restoreBackupInto(txn, backupFile(), includeDirectories: false);
      });

      final keys = (await db.query('settings')).map((r) => r['key']).toSet();
      expect(keys, contains('image_prefix'));
      expect(keys, isNot(contains('output_directory')));
      expect(keys, isNot(contains('result_cache_directory')));
      await db.close();
    });
  });

  group('restore prompts', () {
    /// Prompt data as `getPromptDataRaw` writes it: tags nested per prompt, and
    /// a legacy `tag_id` still pointing at the exporting machine's tag ids.
    Map<String, dynamic> withPrompts(Map<String, dynamic> file) {
      return file
        ..addAll({
          'tags': [
            {'id': 41, 'name': 'Portrait', 'color': 100, 'is_system': 0},
          ],
          'user_prompts': [
            {
              'id': 7,
              'title': 'My prompt',
              'content': 'hello',
              'tag': 'Portrait',
              'tag_id': 41,
              'tags': [
                {'id': 41, 'name': 'Portrait', 'color': 100, 'is_system': 0},
              ],
            },
          ],
          'system_prompts': [
            {
              'id': 9,
              'title': 'My system prompt',
              'content': 'sys',
              'type': 'refiner',
              'tags': [
                {'id': 41, 'name': 'Portrait', 'color': 100, 'is_system': 0},
              ],
            },
          ],
        });
    }

    test('restores prompts, tags and their links', () async {
      final db = await openTestDb();
      await seedChannelWithModel(db);
      // Existing library, so prompt_tags ids are already past the backup's.
      await db.insert('prompt_tags', {'name': 'Existing'});
      await db.insert('prompts', {'title': 'Old', 'content': 'old', 'tag': 'Existing'});

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, withPrompts(backupFile()));
      });

      final tags = await db.query('prompt_tags');
      expect(tags.map((t) => t['name']), ['Portrait']);
      final newTagId = tags.single['id'];

      final prompts = await db.query('prompts');
      expect(prompts.map((p) => p['title']), ['My prompt']);
      expect(prompts.single['tag_id'], newTagId,
          reason: 'tag_id must be remapped to the new tag, not the exporter\'s id');

      final refs = await db.query('prompt_tag_refs');
      expect(refs.single['tag_id'], newTagId);

      final sysRefs = await db.query('system_prompt_tag_refs');
      expect(sysRefs.single['tag_id'], newTagId);
      await db.close();
    });
  });

  group('prompt library import', () {
    /// A prompts-only export as `exportPrompts` writes it.
    Map<String, dynamic> promptsFile() => {
          'export_type': 'prompts_only',
          'version': 1,
          'tags': [
            {'id': 41, 'name': 'Portrait', 'color': 100, 'is_system': 0},
          ],
          'user_prompts': [
            {
              'id': 7,
              'title': 'Imported',
              'content': 'hello',
              'tag': 'Portrait',
              'tag_id': 41,
              'tags': [
                {'id': 41, 'name': 'Portrait', 'color': 100, 'is_system': 0},
              ],
            },
          ],
          'system_prompts': [
            {
              'id': 9,
              'title': 'Imported system',
              'content': 'sys',
              'type': 'refiner',
              'tags': [
                {'id': 41, 'name': 'Portrait', 'color': 100, 'is_system': 0},
              ],
            },
          ],
        };

    test('merge keeps existing prompts and links the new ones', () async {
      final db = await openTestDb();
      await db.insert('prompt_tags', {'name': 'Existing'});
      await db.insert('prompts', {'title': 'Old', 'content': 'old', 'tag': 'Existing'});

      await db.transaction((txn) async {
        await DatabaseService().importPromptDataInto(txn, promptsFile());
      });

      final prompts = await db.query('prompts');
      expect(prompts.map((p) => p['title']), containsAll(['Old', 'Imported']));

      final imported = prompts.firstWhere((p) => p['title'] == 'Imported');
      final portrait = (await db.query('prompt_tags', where: 'name = ?', whereArgs: ['Portrait'])).single;
      expect(imported['tag_id'], portrait['id']);
      expect((await db.query('prompt_tag_refs')).single['tag_id'], portrait['id']);
      await db.close();
    });

    test('replace clears the old library', () async {
      final db = await openTestDb();
      await db.insert('prompt_tags', {'name': 'Existing'});
      await db.insert('prompts', {'title': 'Old', 'content': 'old', 'tag': 'Existing'});

      await db.transaction((txn) async {
        await DatabaseService().importPromptDataInto(txn, promptsFile(), replace: true);
      });

      expect((await db.query('prompts')).map((p) => p['title']), ['Imported']);
      expect((await db.query('prompt_tags')).map((t) => t['name']), ['Portrait']);
      expect((await db.query('system_prompt_tag_refs')).length, 1);
      await db.close();
    });

    test('a full backup can also be imported as prompt data', () async {
      final db = await openTestDb();
      // A full backup carries the same prompt keys plus table data the prompt
      // importer should simply ignore.
      final fullBackup = backupFile()..addAll(promptsFile()..remove('export_type'));

      await db.transaction((txn) async {
        await DatabaseService().importPromptDataInto(txn, fullBackup);
      });

      expect((await db.query('prompts')).map((p) => p['title']), ['Imported']);
      expect((await db.query('llm_channels')), isEmpty,
          reason: 'prompt import must not touch channels');
      await db.close();
    });
  });

  group('validation', () {
    // These reject before any database access, so the singleton is never opened.
    test('rejects a prompt-library export', () async {
      expect(
        () => DatabaseService().restoreBackup({
          'export_type': 'prompts_only',
          'version': 1,
          'tags': [],
          'user_prompts': [],
          'system_prompts': [],
        }),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.error, 'error', BackupFormatError.promptsOnly)),
      );
    });

    test('rejects an unrelated JSON file', () async {
      expect(
        () => DatabaseService().restoreBackup({'hello': 'world'}),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.error, 'error', BackupFormatError.notABackup)),
      );
    });

    test('rejects a backup from a newer app', () async {
      expect(
        () => DatabaseService().restoreBackup({
          'export_type': 'full_backup',
          'schema_version': DatabaseService.dbVersion + 1,
          'settings': [],
        }),
        throwsA(isA<BackupFormatException>()
            .having((e) => e.error, 'error', BackupFormatError.newerSchema)),
      );
    });

    test('accepts a legacy backup with no version stamp', () async {
      final db = await openTestDb();
      final legacy = backupFile()
        ..remove('export_type')
        ..remove('schema_version');

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, legacy);
      });

      expect((await db.query('llm_channels')).length, 1);
      await db.close();
    });
  });
}
