import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/database_service.dart';
import '../db/repositories/image_layer_repository.dart';
import 'directory_access_service.dart';
import 'persistent_media_service.dart';

/// Startup-only migration, before states, watchers and task recovery exist.
/// Copy first, commit references/settings together, never delete old files.
class LegacyResultMigration {
  LegacyResultMigration({
    DatabaseService? database,
    PersistentMediaService? storage,
    DirectoryAccessService? access,
  }) : _db = database ?? DatabaseService(),
       _storage = storage ?? PersistentMediaService.instance,
       _access = access ?? DirectoryAccessService.instance;

  final DatabaseService _db;
  final PersistentMediaService _storage;
  final DirectoryAccessService _access;

  Future<int> run() async {
    final old = await _db.getSetting('result_cache_directory');
    final legacy = await _db.getSetting('legacy_result_cache_directory');
    if ((old == null || old.isEmpty) && (legacy == null || legacy.isEmpty)) return 0;
    final target = (await _storage.resultsDirectory()).path;
    final roots = {old, legacy}
        .whereType<String>()
        .where((root) => root.isNotEmpty && p.normalize(root) != p.normalize(target))
        .toSet();
    if (roots.isEmpty) return 0;

    final paths = <String, String>{};
    for (final root in roots) {
      if (p.isWithin(root, target) || p.isWithin(target, root)) {
        throw FileSystemException('Legacy and persistent result directories overlap', root);
      }
      // A persisted path is not an OS grant. No startup authorization dialog.
      final status = await _access.restore(root);
      if (status != DirectoryAccessStatus.available) {
        throw FileSystemException('Legacy results need directory authorization', root);
      }
      if (await FileSystemEntity.type(root, followLinks: false) != FileSystemEntityType.directory) {
        throw FileSystemException('Legacy results directory is missing or is a link', root);
      }
      final realRoot = await Directory(root).resolveSymbolicLinks();
      final realTarget = await Directory(target).resolveSymbolicLinks();
      if (realRoot == realTarget ||
          p.isWithin(realRoot, realTarget) ||
          p.isWithin(realTarget, realRoot)) {
        throw FileSystemException('Legacy and persistent result directories overlap', root);
      }
      await for (final entry in Directory(root).list(recursive: true, followLinks: false)) {
        if (entry is Link) {
          throw FileSystemException('Legacy result symlink requires manual recovery', entry.path);
        }
        if (entry is! File || entry.path.endsWith('.partial')) continue;
        paths[entry.path] = await _storage.migrateResult(entry.path);
      }
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      final replacements = {...paths, for (final root in roots) root: target};
      // Rewrite exact JSON string values, never substrings in prose, URLs or IDs.
      await _rewrite(txn, 'tasks', 'id', [
        'image_path',
        'result_path',
        'parameters',
        'batch_state',
      ], replacements);
      await _rewrite(txn, 'assistant_sessions', 'id', ['ref_images'], replacements);
      await _rewrite(txn, 'assistant_messages', 'id', ['message'], replacements);
      for (final entry in paths.entries) {
        await txn.update(
          'image_layers',
          {'path': entry.value},
          where: 'path = ?',
          whereArgs: [entry.key],
        );
      }
      final output = await txn.query('settings', where: 'key = ?', whereArgs: ['output_directory']);
      if (output.isNotEmpty && roots.contains(output.single['value'])) {
        await txn.update(
          'settings',
          {'value': target},
          where: 'key = ?',
          whereArgs: ['output_directory'],
        );
      }
      await txn.insert('settings', {
        'key': 'result_cache_directory',
        'value': target,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('settings', where: 'key = ?', whereArgs: ['legacy_result_cache_directory']);
    });
    await ImageLayerRepository(db: _db).loadPaths();
    return paths.length;
  }

  Future<void> _rewrite(
    DatabaseExecutor txn,
    String table,
    String key,
    List<String> columns,
    Map<String, String> paths,
  ) async {
    for (final row in await txn.query(table, columns: [key, ...columns])) {
      final changes = <String, Object?>{};
      for (final column in columns) {
        final raw = row[column];
        if (raw is! String || raw.isEmpty) continue;
        Object? value;
        try {
          value = jsonDecode(raw);
        } on FormatException {
          // Old task rows may contain a single plain path, not a JSON list.
          if (paths.containsKey(raw)) changes[column] = paths[raw];
          continue;
        }
        final rewritten = _replace(value, paths);
        if (jsonEncode(rewritten) != jsonEncode(value)) changes[column] = jsonEncode(rewritten);
      }
      if (changes.isNotEmpty) {
        await txn.update(table, changes, where: '$key = ?', whereArgs: [row[key]]);
      }
    }
  }

  Object? _replace(Object? value, Map<String, String> paths) {
    if (value is String) return paths[value] ?? value;
    if (value is List) return value.map((item) => _replace(item, paths)).toList();
    if (value is Map<String, dynamic>) {
      return value.map((key, item) {
        // Prose can itself be a path. Preserve it, including provider IDs.
        const textKeys = {'prompt', 'content', 'text', 'description', 'name', 'id'};
        final literal =
            item is String && (textKeys.contains(key) || key.endsWith('Id') || key.endsWith('_id'));
        return MapEntry(key, literal ? item : _replace(item, paths));
      });
    }
    return value;
  }
}
