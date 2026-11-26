import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/app_paths.dart';
import '../db/database_service.dart';
import '../llm/channel_upload_config.dart';
import 'credential_protection.dart';

/// Bootstrap-only, after explicit confirmation and before any live DB consumer.
/// Keeps a SQLite snapshot before removing only the three protected credentials.
class CredentialRecoveryService {
  CredentialRecoveryService({Future<String> Function()? dataDirectory, DatabaseFactory? factory})
    : _directory = dataDirectory ?? AppPaths.getDataDirectory,
      _injectedFactory = factory;
  final Future<String> Function() _directory;
  final DatabaseFactory? _injectedFactory;

  DatabaseFactory get _factory {
    if (_injectedFactory != null) return _injectedFactory;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactory;
  }

  Future<void> reset() async {
    Database? db;
    try {
      final root = await _directory();
      final path = p.join(root, 'joycai_workbench.db');
      if (!await File(path).exists()) throw const CredentialProtectionException();
      final factory = _factory;
      db = await factory.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
      if (await db.getVersion() != DatabaseService.dbVersion) {
        throw const CredentialProtectionException();
      }
      final snapshots = await Directory(p.join(root, 'credential-recovery'))
          .create(recursive: true);
      await DatabaseService.restrictToOwner(null, directory: snapshots.path);
      final snapshot = await snapshots.createTemp('before-reset-');
      await DatabaseService.restrictToOwner(null, directory: snapshot.path);
      // VACUUM includes committed WAL data; never copy a live SQLite file alone.
      // Apple's SQLite rejects an existing output file; let VACUUM create it.
      final snapshotPath = p.join(snapshot.path, 'joycai_workbench.db');
      await db.execute('VACUUM INTO ?', [snapshotPath]);
      await DatabaseService.restrictToOwner(snapshotPath);
      final saved = await factory.openDatabase(
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
        for (final row in await txn.query('llm_channels', columns: ['id', 'routes'])) {
          await txn.update(
            'llm_channels',
            {'routes': ChannelUploadConfig.mapDocumentKey(row['routes'] as String?, (_) => '')},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
        for (final key in CredentialProtection.settingKeys) {
          await txn.delete('settings', where: 'key = ?', whereArgs: [key]);
        }
        await txn.insert('settings', {
          'key': 'mcp_enabled',
          'value': 'false',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      final checkpoint = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if (checkpoint.isNotEmpty && checkpoint.first.values.first != 0) {
        throw const CredentialProtectionException();
      }
    } catch (_) {
      throw const CredentialProtectionException();
    } finally {
      await db?.close();
    }
  }
}
