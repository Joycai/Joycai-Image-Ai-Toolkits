import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/app_paths.dart';
import '../db/database_service.dart';
import 'credential_protection.dart';

/// Bootstrap-only, after explicit confirmation and before any live DB consumer.
/// Keeps a SQLite snapshot before removing only the three protected credentials.
class CredentialRecoveryService {
  CredentialRecoveryService({Future<String> Function()? dataDirectory, this._factory})
    : _directory = dataDirectory ?? AppPaths.getDataDirectory;
  final Future<String> Function() _directory;
  final DatabaseFactory? _factory;

  Future<void> reset() async {
    Database? db;
    try {
      final root = await _directory();
      final path = p.join(root, 'joycai_workbench.db');
      if (!await File(path).exists()) throw const CredentialProtectionException();
      sqfliteFfiInit();
      db = await (_factory ?? databaseFactoryFfi).openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      if (await db.getVersion() != DatabaseService.dbVersion) {
        throw const CredentialProtectionException();
      }
      final snapshots = await Directory(p.join(root, 'credential-recovery'))
          .create(recursive: true);
      final snapshot = await snapshots.createTemp('before-reset-');
      // VACUUM includes committed WAL data; never copy a live SQLite file alone.
      final snapshotPath = p.join(snapshot.path, 'joycai_workbench.db');
      await db.execute('VACUUM INTO ?', [snapshotPath]);
      final saved = await (_factory ?? databaseFactoryFfi).openDatabase(
        snapshotPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      try {
        if ((await saved.rawQuery('PRAGMA quick_check')).single.values.single != 'ok') {
          throw const CredentialProtectionException();
        }
      } finally {
        await saved.close();
      }
      await db.rawQuery('PRAGMA secure_delete = ON');
      await db.transaction((txn) async {
        await txn.update('llm_channels', {'api_key': ''});
        for (final key in CredentialProtection.settingKeys) {
          await txn.delete('settings', where: 'key = ?', whereArgs: [key]);
        }
        await txn.insert('settings', {
          'key': 'mcp_enabled',
          'value': 'false',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      throw const CredentialProtectionException();
    } finally {
      await db?.close();
    }
  }
}
