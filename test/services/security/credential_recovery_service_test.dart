import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/security/credential_protection.dart';
import 'package:joycai_image_ai_toolkits/services/security/credential_recovery_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Database db;
  late CredentialRecoveryService recovery;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('joycai-credential-reset-');
    db = await databaseFactoryFfi.openDatabase(
      p.join(root.path, 'joycai_workbench.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.setVersion(DatabaseService.dbVersion);
    await db.execute(
      'CREATE TABLE llm_channels (id INTEGER PRIMARY KEY, api_key TEXT, display_name TEXT, routes TEXT)',
    );
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE prompts (id INTEGER PRIMARY KEY, text TEXT)');
    await db.insert('llm_channels', {
      'id': 1,
      'api_key': 'joycai-secret:win-dpapi:v1:lost',
      'display_name': 'Keep channel',
      'routes': '{"mediaUpload":{"apiKey":"lost-upload"}}',
    });
    await db.insert('prompts', {'id': 1, 'text': 'Keep prompt'});
    for (final key in ['proxy_password', 'mcp_token', 'output_directory']) {
      await db.insert('settings', {'key': key, 'value': 'keep-$key'});
    }
    recovery = CredentialRecoveryService(
      dataDirectory: () async => root.path,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('snapshots before clearing only credentials, disables MCP and preserves data', () async {
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await recovery.reset();
    expect((await db.query('llm_channels')).single, {
      'id': 1,
      'api_key': '',
      'display_name': 'Keep channel',
      'routes': '{"mediaUpload":{"apiKey":""}}',
    });
    expect((await db.query('prompts')).single['text'], 'Keep prompt');
    final settings = {for (final row in await db.query('settings')) row['key']: row['value']};
    expect(settings, {'output_directory': 'keep-output_directory', 'mcp_enabled': 'false'});
    final snapshots = await Directory(p.join(root.path, 'credential-recovery'))
        .list(recursive: true)
        .where((e) => e is File)
        .toList();
    final saved = await databaseFactoryFfi.openDatabase(
      snapshots.single.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      expect(
        (await saved.query('llm_channels')).single['api_key'],
        'joycai-secret:win-dpapi:v1:lost',
      );
      expect((await saved.query('llm_channels')).single['routes'], contains('lost-upload'));
      expect(await saved.query('prompts'), await db.query('prompts'));
    } finally {
      await saved.close();
    }
  });

  test('snapshot failure leaves credentials and non-secret data unchanged', () async {
    await File(p.join(root.path, 'credential-recovery')).writeAsString('blocks directory');
    await expectLater(recovery.reset(), throwsA(isA<CredentialProtectionException>()));
    expect((await db.query('llm_channels')).single['api_key'], 'joycai-secret:win-dpapi:v1:lost');
    expect((await db.query('prompts')).single['text'], 'Keep prompt');
  });

  test(
    'clears macOS Keychain v1 envelopes while preserving non-secret data and snapshot',
    () async {
      await db.update('llm_channels', {
        'api_key': 'joycai-secret:v1:lost-mac-key',
        'routes': '{"mediaUpload":{"apiKey":"joycai-secret:v1:lost-mac-upload"}}',
      });
      await db.update('settings', {
        'value': 'joycai-secret:v1:lost-proxy',
      }, where: "key = 'proxy_password'");
      await db.update('settings', {
        'value': 'joycai-secret:v1:lost-mcp',
      }, where: "key = 'mcp_token'");

      await recovery.reset();
      expect((await db.query('llm_channels')).single, {
        'id': 1,
        'api_key': '',
        'display_name': 'Keep channel',
        'routes': '{"mediaUpload":{"apiKey":""}}',
      });
      expect((await db.query('prompts')).single['text'], 'Keep prompt');
      final settings = {for (final row in await db.query('settings')) row['key']: row['value']};
      expect(settings, {'output_directory': 'keep-output_directory', 'mcp_enabled': 'false'});
      final snapshots = await Directory(p.join(root.path, 'credential-recovery'))
          .list(recursive: true)
          .where((e) => e is File)
          .toList();
      final saved = await databaseFactoryFfi.openDatabase(
        snapshots.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        expect(
          (await saved.query('llm_channels')).single['api_key'],
          'joycai-secret:v1:lost-mac-key',
        );
        expect((await saved.query('llm_channels')).single['routes'], contains('lost-mac-upload'));
      } finally {
        await saved.close();
      }
    },
  );
}
