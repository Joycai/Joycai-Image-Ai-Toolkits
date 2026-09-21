import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/models/tag.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
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

    test("renumbers a channel's default fee group along with the groups", () async {
      final db = await openTestDb();
      // A group already here, so the restored one cannot keep the file's id.
      await db.insert('fee_groups', {'name': 'Local'});
      final file = backupFile();
      file['fee_groups'] = [
        {'id': 7, 'name': 'Pro', 'billing_mode': 'token'},
      ];
      (file['llm_channels'] as List).first['default_fee_group_id'] = 7;

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, file);
      });

      final group = (await db.query('fee_groups')).single;
      final channel = (await db.query('llm_channels')).single;
      expect(group['id'], isNot(7));
      expect(channel['default_fee_group_id'], group['id']);
      await db.close();
    });

    test('drops a default fee group the backup does not carry', () async {
      final db = await openTestDb();
      final file = backupFile();
      (file['llm_channels'] as List).first['default_fee_group_id'] = 7;

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, file);
      });

      expect((await db.query('llm_channels')).single['default_fee_group_id'], isNull);
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
              // A hand-edited or damaged file: the column is NOT NULL, and
              // this one row must not roll the whole restore back.
              'output_kind': null,
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

      expect((await db.query('system_prompts')).single['output_kind'], 'prompt');

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
      expect(await db.query('llm_channels'), isEmpty,
          reason: 'prompt import must not touch channels');
      await db.close();
    });

    test('a column this build has never heard of costs only that column', () async {
      final db = await openTestDb();
      // The file a later build writes: every row this one knows, plus a column
      // added after it shipped. One such key used to fail its insert inside the
      // import's transaction, so the tags and user prompts went down with it.
      final file = promptsFile();
      (file['system_prompts'] as List).first['delivery_style'] = 'terse';
      (file['user_prompts'] as List).first['pinned_at'] = 1758400000;
      (file['tags'] as List).first['icon'] = 'star';

      await db.transaction((txn) async {
        await DatabaseService().importPromptDataInto(txn, file);
      });

      // `onCreate` seeds a tag and the built-in presets, so these are
      // containment checks: what matters is that the file's rows arrived.
      expect((await db.query('prompts')).map((p) => p['title']), ['Imported']);
      expect((await db.query('system_prompts')).map((p) => p['title']),
          contains('Imported system'));
      expect((await db.query('prompt_tags')).map((t) => t['name']), contains('Portrait'));
      expect((await db.query('prompt_tag_refs')).length, 1,
          reason: 'the links survive too — the row went in whole but for the unknown key');

      // Asserting on a *known* column: `containsKey('pinned_at')` would be
      // vacuous, since a query only ever returns the table's real columns and
      // would pass just as well if the filter had thrown everything away.
      final imported = (await db.query('prompts')).single;
      expect(imported['content'], 'hello',
          reason: 'the row went in whole but for the one key with nowhere to go');
      expect(imported['tag'], 'Portrait');
      await db.close();
    });
  });

  /// The other half of the same bug: what this build *writes* has to stay
  /// readable by the build the user is importing into, which has already
  /// shipped and cannot be taught anything.
  group('prompt library export', () {
    final portrait = PromptTag(id: 41, name: 'Portrait', color: 100);

    SystemPrompt preset(PresetOutputKind kind) => SystemPrompt(
          title: 'Preset',
          content: 'sys',
          type: SystemPrompt.typeRefiner,
          outputKind: kind,
          tags: [portrait],
        );

    test('a prompt-kind preset leaves output_kind out', () {
      final row = preset(PresetOutputKind.prompt).toExportMap();
      expect(row.containsKey('output_kind'), isFalse,
          reason: 'a build older than v47 inserts this row column by column');
      expect(row['title'], 'Preset');
    });

    test('the preset carries its tags', () {
      // With an empty tag list this would pass whether the tags are serialized
      // or thrown away, so the preset here has one and it has to come through.
      final row = preset(PresetOutputKind.prompt).toExportMap();
      expect((row['tags'] as List).single['name'], 'Portrait');
      expect((row['tags'] as List).single['id'], 41);
    });

    test('an analysis preset still carries it', () {
      final row = preset(PresetOutputKind.analysis).toExportMap();
      expect(row['output_kind'], 'analysis',
          reason: 'dropping it would quietly turn the preset into a prompt one');
    });

    test('what is left out reads back as the default', () {
      final row = preset(PresetOutputKind.prompt).toExportMap();
      expect(SystemPrompt.fromMap({...row, 'id': 1}).outputKind, PresetOutputKind.prompt);
    });

    test('a row without output_kind still imports', () async {
      final db = await openTestDb();
      await db.transaction((txn) async {
        await DatabaseService().importPromptDataInto(txn, {
          'export_type': 'prompts_only',
          'version': 1,
          'system_prompts': [preset(PresetOutputKind.prompt).toExportMap()],
        });
      });
      final row = (await db.query('system_prompts', where: 'title = ?', whereArgs: ['Preset'])).single;
      expect(row['output_kind'], 'prompt',
          reason: "the column's default stands in for the key the file left out");
      await db.close();
    });

    test('both export writers hand out the same rows', () {
      // `getPromptDataRaw` (the full backup) and `exportPrompts` (the
      // prompt-library file) are this function plus, in one case, two extra
      // keys. Testing it is testing both — which is the point of it existing:
      // when `toExportMap` arrived, only one of the two writers was taught
      // about it, and the bug this branch fixes survived in the other.
      final data = promptLibraryExport(
        tags: [portrait],
        userPrompts: [Prompt(id: 7, title: 'Mine', content: 'hello', tags: [portrait])],
        systemPrompts: [preset(PresetOutputKind.prompt), preset(PresetOutputKind.analysis)],
      );

      expect((data['tags'] as List).single['name'], 'Portrait');

      final user = (data['user_prompts'] as List).single;
      expect(user['content'], 'hello');
      expect((user['tags'] as List).single['name'], 'Portrait');

      final presets = (data['system_prompts'] as List).cast<Map<String, dynamic>>();
      expect(presets.first.containsKey('output_kind'), isFalse);
      expect(presets.last['output_kind'], 'analysis');
      expect((presets.first['tags'] as List).single['name'], 'Portrait');
    });

    test('a full backup restores a row that left output_kind out', () async {
      // The second door: a backup is importable through the Prompt Library too,
      // which has no `schema_version` gate, so `getPromptDataRaw` has to strip
      // the default exactly as the prompt-library export does.
      final db = await openTestDb();
      final backup = backupFile()
        ..addAll({
          'tags': [],
          'user_prompts': [],
          'system_prompts': [preset(PresetOutputKind.prompt).toExportMap()],
        });

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, backup);
      });

      final row = (await db.query('system_prompts', where: 'title = ?', whereArgs: ['Preset'])).single;
      expect(row['output_kind'], 'prompt');
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

  group('channel routes in backups (v45)', () {
    test('a pre-route backup restores and reads its routes as before',
        () async {
      final db = await openTestDb();
      final legacy = backupFile()..['schema_version'] = 44;
      (legacy['llm_channels'] as List).first
        ..['type'] = 'dashscope-native'
        ..['endpoint'] = 'https://dashscope.aliyuncs.com/api/v1';
      (legacy['llm_models'] as List).first
        ..['tag'] = 'chat'
        ..['model_id'] = 'qwen-plus'
        ..['wire_protocol'] = 'anthropic-chat';

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, legacy);
      });

      final channel = (await db.query('llm_channels')).single;
      expect(channel['routes'], isNull);
      final routes = ChannelRoutes.resolve(channel['type'] as String,
          channel['endpoint'] as String, channel['routes'] as String?);
      expect(routes.kinds,
          [RouteKind.dashscope, RouteKind.chat, RouteKind.anthropic]);
      final model = LLMModel.fromMap((await db.query('llm_models')).single);
      expect(ModelRoutes.requestRoute(model, routes), RouteKind.anthropic);
      await db.close();
    });

    test('routes and parked params round-trip through export and restore',
        () async {
      final db = await openTestDb();
      final routes = ChannelRoutes.create(Platforms.byId(Platforms.newapi),
          'https://relay.example.com', [RouteKind.chat, RouteKind.gemini],
          paths: {RouteKind.gemini: 'https://g.example.com/v1beta'});
      final file = backupFile();
      (file['llm_channels'] as List).first
        ..['type'] = routes.primaryVendorId
        ..['endpoint'] = routes.primaryAddress
        ..['routes'] = routes.encode();
      (file['llm_models'] as List).first
        ..['tag'] = 'chat'
        ..['active_route'] = 'gemini'
        ..['route_params'] = '{"chat":{"max_output_tokens":4096}}';

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, file);
      });

      final channel = (await db.query('llm_channels')).single;
      expect(channel['routes'], routes.encode());
      final model = (await db.query('llm_models')).single;
      expect(model['active_route'], 'gemini');
      expect(model['route_params'], '{"chat":{"max_output_tokens":4096}}');
      await db.close();
    });

    test('a redacted key survives a restore across the route migration',
        () async {
      // This machine still holds the channel as written before routes, with
      // a MiniMax endpoint whose primary face is canonicalized on save.
      final db = await openTestDb();
      await db.insert('llm_channels', {
        'display_name': 'MiniMax',
        'endpoint': 'https://api.minimaxi.com/v1/',
        'api_key': 'live-key',
        'type': 'minimax-api',
      });
      final routes = ChannelRoutes.legacy('minimax-api', 'https://api.minimaxi.com/v1/');
      final file = backupFile(channelName: 'MiniMax');
      (file['llm_channels'] as List).first
        ..['type'] = routes.primaryVendorId
        ..['endpoint'] = routes.primaryAddress
        ..['routes'] = routes.encode();
      (file['llm_models'] as List).clear();

      await db.transaction((txn) async {
        await DatabaseService().restoreBackupInto(txn, file);
      });

      expect((await db.query('llm_channels')).single['api_key'], 'live-key');
      await db.close();
    });

    test('this build writes schema 47, which a v46 build rejects', () {
      expect(DatabaseService.dbVersion, 47);
    });
  });
}
