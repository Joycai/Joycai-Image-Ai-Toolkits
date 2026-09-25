import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// The credentials that stay in plain text in the database (S1): the proxy
/// password leaves no copy in a backup and survives a restore of one, and on
/// macOS / Linux the database file is the signed-in user's alone.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final Directory dataDir = usePrivateDataDir('joycai_data_secrets_test');

  test('a full backup carries no proxy password', () async {
    final db = DatabaseService();
    await db.saveSetting('proxy_password', 'hunter2');
    await db.saveSetting('proxy_username', 'me');

    final data = await db.getAllDataRaw();
    final settings = {for (final r in data['settings'] as List) r['key']: r['value']};
    expect(settings['proxy_password'], '');
    expect(settings['proxy_username'], 'me', reason: 'only the secret is redacted');
    expect(await db.getSetting('proxy_password'), 'hunter2', reason: 'the live row is untouched');
  });

  group('restore', () {
    Future<Database> openMemory() async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: DatabaseService.dbVersion,
          onCreate: (db, version) => DatabaseMigration.onCreate(db),
        ),
      );
      addTearDown(db.close);
      return db;
    }

    Map<String, dynamic> file(String password) => {
      'export_type': 'full_backup',
      'schema_version': DatabaseService.dbVersion,
      'settings': [
        {'key': 'proxy_password', 'value': password},
        {'key': 'proxy_url', 'value': 'http://proxy:8080'},
      ],
      'llm_channels': [],
      'llm_models': [],
      'fee_groups': [],
    };

    Future<String?> password(Database db) async {
      final rows = await db.query('settings', where: 'key = ?', whereArgs: ['proxy_password']);
      return rows.isEmpty ? null : rows.first['value'] as String?;
    }

    test('a redacted password keeps the one this machine has', () async {
      final db = await openMemory();
      await db.insert('settings', {'key': 'proxy_password', 'value': 'live'});
      await db.transaction((txn) => DatabaseService().restoreBackupInto(txn, file('')));
      expect(await password(db), 'live');
      final url = await db.query('settings', where: 'key = ?', whereArgs: ['proxy_url']);
      expect(url.single['value'], 'http://proxy:8080');
    });

    test('a password the file does carry wins', () async {
      final db = await openMemory();
      await db.insert('settings', {'key': 'proxy_password', 'value': 'live'});
      await db.transaction((txn) => DatabaseService().restoreBackupInto(txn, file('from-file')));
      expect(await password(db), 'from-file');
    });

    test('nothing live and nothing in the file stays blank', () async {
      final db = await openMemory();
      await db.transaction((txn) => DatabaseService().restoreBackupInto(txn, file('')));
      expect(await password(db), '');
    });
  });

  test('the database and its folder are private to their owner', () async {
    if (!(Platform.isMacOS || Platform.isLinux)) return;
    await DatabaseService().database;
    final dbFile = File(p.join(dataDir.path, 'joycai_workbench.db'));
    expect(dbFile.existsSync(), isTrue);
    expect(dbFile.statSync().mode & 0x1FF, 0x180, reason: 'rw------- (600)');
    expect(dataDir.statSync().mode & 0x1FF, 0x1C0, reason: 'rwx------ (700)');
  }, skip: Platform.isWindows);
}
