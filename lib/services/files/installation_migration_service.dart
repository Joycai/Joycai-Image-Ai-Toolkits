import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_paths.dart';
import '../db/database_migrations.dart';
import '../db/database_service.dart';

enum InstallationMigrationError { invalidSource, newerSchema, sourceChanged, invalidDatabase }

class InstallationMigrationException implements Exception {
  const InstallationMigrationException(this.reason);
  final InstallationMigrationError reason;
}

/// Runs BEFORE DatabaseService/AppState/queue construction. The source and the
/// current installation are never replaced: activation switches one pointer.
/// No app-container migration manifest is needed; explicit selection also works
/// for users whose sandbox container already exists.
class InstallationMigrationService {
  InstallationMigrationService({
    Future<String> Function()? supportDirectory,
    DatabaseFactory? factory,
  }) : _supportDirectory = supportDirectory ?? AppPaths.getSupportDirectory,
       _injectedFactory = factory;

  final Future<String> Function() _supportDirectory;
  final DatabaseFactory? _injectedFactory;
  DatabaseFactory get _factory => _injectedFactory ?? databaseFactory;
  bool _running = false;
  static const databaseName = 'joycai_workbench.db';
  static const _ownedDirectories = ['media', 'mcp-inputs', 'fonts', 'usage-journal'];

  Future<bool> shouldOffer() async {
    final root = await _supportDirectory();
    return await File(p.join(root, 'request-installation-import')).exists() ||
        !await File(p.join(root, 'installation-choice-made')).exists();
  }

  Future<void> requestOnNextLaunch() async {
    final root = await _supportDirectory();
    await Directory(root).create(recursive: true);
    await File(p.join(root, 'request-installation-import')).writeAsString('1', flush: true);
  }

  Future<void> finishChoice() async {
    final root = await _supportDirectory();
    await Directory(root).create(recursive: true);
    await File(p.join(root, 'installation-choice-made')).writeAsString('1', flush: true);
    final request = File(p.join(root, 'request-installation-import'));
    if (await request.exists()) await request.delete();
  }

  Future<String> currentDirectory() async =>
      AppPaths.resolveDataDirectory(await _supportDirectory());

  Future<String> importDirectory(String sourcePath) async {
    if (_running) throw StateError('Installation import already running');
    _running = true;
    Directory? destination;
    bool activated = false;
    Database? source;
    Database? copy;
    try {
      final support = await _supportDirectory();
      await Directory(support).create(recursive: true);
      final sourceRoot = Directory(p.normalize(p.absolute(sourcePath)));
      final realSource = await sourceRoot.resolveSymbolicLinks();
      final realSupport = await Directory(support).resolveSymbolicLinks();
      if (realSource == realSupport ||
          p.isWithin(realSource, realSupport) ||
          p.isWithin(realSupport, realSource) ||
          await FileSystemEntity.type(sourceRoot.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw const InstallationMigrationException(InstallationMigrationError.invalidSource);
      }
      final sourceDatabase = p.join(sourceRoot.path, databaseName);
      if (await FileSystemEntity.type(sourceDatabase, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const InstallationMigrationException(InstallationMigrationError.invalidSource);
      }
      for (final suffix in ['-wal', '-shm', '-journal']) {
        if (await FileSystemEntity.type('$sourceDatabase$suffix', followLinks: false) ==
            FileSystemEntityType.link) {
          throw const InstallationMigrationException(InstallationMigrationError.invalidSource);
        }
      }
      // Never copy a database file blindly: committed rows may still be in WAL.
      // readOnly avoids upgrading or otherwise writing the source schema.
      source = await _factory.openDatabase(
        sourceDatabase,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      await _validate(source);
      final version = await source.getVersion();
      if (version > DatabaseService.dbVersion) {
        throw const InstallationMigrationException(InstallationMigrationError.newerSchema);
      }
      if (version < 1) {
        throw const InstallationMigrationException(InstallationMigrationError.invalidDatabase);
      }
      final dataVersion = await source.rawQuery('PRAGMA data_version');
      final id = const Uuid().v4();
      destination = Directory(p.join(support, 'installations', id));
      await destination.create(recursive: true);
      final targetDatabase = p.join(destination.path, databaseName);
      // Apple's SQLite rejects an existing output, even an empty file. Protect
      // the staging directory first and let VACUUM create its own database.
      await DatabaseService.restrictToOwner(null, directory: destination.path);
      await source.execute('VACUUM INTO ?', [targetDatabase]);

      final replacements = <String, String>{};
      final digests = <String, String>{};
      final inventory = <String>{};
      for (final folder in _ownedDirectories) {
        final from = p.join(sourceRoot.path, folder);
        final kind = await FileSystemEntity.type(from, followLinks: false);
        if (kind == FileSystemEntityType.notFound) continue;
        if (kind != FileSystemEntityType.directory) {
          throw const InstallationMigrationException(InstallationMigrationError.invalidSource);
        }
        final to = p.join(destination.path, folder);
        await Directory(to).create(recursive: true);
        inventory.add(from);
        replacements[from] = to;
        await for (final entry in Directory(from).list(recursive: true, followLinks: false)) {
          if (entry is Link) {
            throw const InstallationMigrationException(InstallationMigrationError.invalidSource);
          }
          final target = p.join(destination.path, p.relative(entry.path, from: sourceRoot.path));
          if (entry is Directory) {
            inventory.add(entry.path);
            await Directory(target).create(recursive: true);
            replacements[entry.path] = target;
          } else if (entry is File) {
            if (entry.path.endsWith('.partial') || entry.path.endsWith('.part')) continue;
            inventory.add(entry.path);
            final digest = (await sha256.bind(entry.openRead()).first).toString();
            final out = File('$target.partial');
            await out.parent.create(recursive: true);
            final sink = out.openWrite();
            try {
              await sink.addStream(entry.openRead());
              await sink.flush();
            } finally {
              await sink.close();
            }
            if ((await sha256.bind(out.openRead()).first).toString() != digest) {
              throw const InstallationMigrationException(InstallationMigrationError.sourceChanged);
            }
            await out.rename(target);
            digests[entry.path] = digest;
            replacements[entry.path] = target;
          }
        }
      }
      // Upgrade only the isolated copy, using the same migrations as normal
      // startup. Reject unrelated SQLite files before invoking any migration.
      copy = await _factory.openDatabase(
        targetDatabase,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: DatabaseService.dbVersion,
          onUpgrade: DatabaseMigration.migrate,
        ),
      );
      await copy.transaction((txn) async {
        await _rewrite(txn, 'tasks', 'id', [
          'image_path',
          'result_path',
          'parameters',
          'batch_state',
        ], replacements);
        await _rewrite(txn, 'assistant_sessions', 'id', ['ref_images'], replacements);
        await _rewrite(txn, 'assistant_messages', 'id', ['message'], replacements);
        for (final table in ['image_layers', 'source_directories']) {
          for (final row in await txn.query(table)) {
            final path = row['path'];
            if (replacements.containsKey(path)) {
              await txn.update(
                table,
                {'path': replacements[path]},
                where: 'path = ?',
                whereArgs: [path],
              );
            }
          }
        }
        const pathSettings = {
          'output_directory',
          'result_cache_directory',
          'legacy_result_cache_directory',
          'browser_source_directories',
          'browser_active_directories',
          'knowledge_base_path',
        };
        for (final row in await txn.query('settings')) {
          if (!pathSettings.contains(row['key'])) continue;
          final raw = row['value'];
          if (raw is! String) continue;
          final value = _rewriteValue(raw, replacements);
          if (value != raw) {
            await txn.update(
              'settings',
              {'value': value},
              where: 'key = ?',
              whereArgs: [row['key']],
            );
          }
        }
        // OS grants are machine-local. Imported MCP credentials/allowlists must
        // never silently start a server on the new installation.
        for (final key in ['mcp_roots', 'mcp_token', 'mcp_port']) {
          await txn.delete('settings', where: 'key = ?', whereArgs: [key]);
        }
        await txn.insert('settings', {
          'key': 'mcp_enabled',
          'value': 'false',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await _validate(copy);
      // This PRAGMA returns a row; Darwin's driver rejects it via execute().
      final checkpoint = await copy.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      if (checkpoint.isEmpty || checkpoint.single['busy'] != 0) {
        throw StateError('Imported database checkpoint did not complete');
      }
      await copy.close();
      copy = null;
      // A running old app may change media independently of SQLite. Verify both
      // before activation; the UI requires the old app to remain closed.
      final currentInventory = <String>{};
      for (final folder in _ownedDirectories) {
        final dir = Directory(p.join(sourceRoot.path, folder));
        if (!await dir.exists()) continue;
        currentInventory.add(dir.path);
        await for (final entry in dir.list(recursive: true, followLinks: false)) {
          if (entry is Link) {
            throw const InstallationMigrationException(InstallationMigrationError.sourceChanged);
          }
          if (entry is File && (entry.path.endsWith('.partial') || entry.path.endsWith('.part'))) {
            continue;
          }
          currentInventory.add(entry.path);
        }
      }
      if (inventory.length != currentInventory.length || !inventory.containsAll(currentInventory)) {
        throw const InstallationMigrationException(InstallationMigrationError.sourceChanged);
      }
      for (final entry in digests.entries) {
        if ((await sha256.bind(File(entry.key).openRead()).first).toString() != entry.value) {
          throw const InstallationMigrationException(InstallationMigrationError.sourceChanged);
        }
      }
      if (jsonEncode(await source.rawQuery('PRAGMA data_version')) != jsonEncode(dataVersion)) {
        throw const InstallationMigrationException(InstallationMigrationError.sourceChanged);
      }
      await source.close();
      source = null;
      final previous = await currentDirectory();
      await File(p.join(destination.path, 'installation-import.json')).writeAsString(
        jsonEncode({
          'source': sourceRoot.path,
          'previous': previous,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await DatabaseService.restrictToOwner(targetDatabase, directory: destination.path);
      // No awaits that can fail after the commit point: once switched, this
      // complete copy is authoritative, including after a process crash.
      final pointer = File(p.join(support, 'active-installation.$id.partial'));
      await pointer.writeAsString(id, flush: true);
      await pointer.rename(p.join(support, 'active-installation'));
      activated = true;
      return destination.path;
    } finally {
      try {
        await copy?.close();
      } finally {
        try {
          await source?.close();
        } finally {
          _running = false;
          if (!activated && destination != null && await destination.exists()) {
            await destination.delete(recursive: true);
          }
        }
      }
    }
  }

  Future<void> _validate(Database db) async {
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((row) => row['name'])
        .toSet();
    if (integrity.length != 1 ||
        integrity.single.values.single != 'ok' ||
        !tables.containsAll({'settings', 'tasks', 'llm_channels', 'llm_models', 'prompts'})) {
      throw const InstallationMigrationException(InstallationMigrationError.invalidDatabase);
    }
  }

  Future<void> _rewrite(
    DatabaseExecutor db,
    String table,
    String key,
    List<String> columns,
    Map<String, String> paths,
  ) async {
    for (final row in await db.query(table, columns: [key, ...columns])) {
      final changes = <String, Object?>{};
      for (final column in columns) {
        final raw = row[column];
        if (raw is! String) continue;
        final value = _rewriteValue(raw, paths);
        if (raw != value) changes[column] = value;
      }
      if (changes.isNotEmpty) {
        await db.update(table, changes, where: '$key = ?', whereArgs: [row[key]]);
      }
    }
  }

  String _rewriteValue(String raw, Map<String, String> paths) {
    if (paths.containsKey(raw)) return paths[raw]!;
    try {
      final value = jsonDecode(raw);
      final replaced = _replace(value, paths);
      return jsonEncode(value) == jsonEncode(replaced) ? raw : jsonEncode(replaced);
    } on FormatException {
      return raw;
    }
  }

  Object? _replace(Object? value, Map<String, String> paths) {
    if (value is String) return paths[value] ?? value;
    if (value is List) return value.map((item) => _replace(item, paths)).toList();
    if (value is Map<String, dynamic>) {
      return value.map((key, item) {
        const literalKeys = {'prompt', 'content', 'text', 'description', 'name', 'id'};
        final literal =
            item is String &&
            (literalKeys.contains(key) || key.endsWith('Id') || key.endsWith('_id'));
        return MapEntry(key, literal ? item : _replace(item, paths));
      });
    }
    return value;
  }
}
