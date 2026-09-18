import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../models/image_layer.dart';
import '../database_service.dart';

/// Saved layer decompositions (`image_layers`, v46): which files came out of
/// one decomposition, in what order, and where each layer sits on the base.
///
/// Rows are keyed by file path, so the app's own renames and moves carry
/// them along ([move]); a file changed behind the app's back leaves an
/// orphan row, which [setFor] filters out by existence.
class ImageLayerRepository {
  ImageLayerRepository({DatabaseService? db}) : _dbService = db ?? DatabaseService();

  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  /// Every path that has a row → its stacking order, for the gallery's
  /// layer badge. A new map on every change — never mutated — so a listener
  /// can compare by identity. Filled by [loadPaths] when the database opens;
  /// the table holds a few rows per decomposition, so all of it fits.
  static final ValueNotifier<Map<String, int>> layeredPaths =
      ValueNotifier(const <String, int>{});

  /// Fills [layeredPaths] from the table.
  Future<void> loadPaths() async {
    final db = await _db;
    final rows = await db.query('image_layers', columns: ['path', 'z_index']);
    layeredPaths.value = {
      for (final r in rows) r['path'] as String: r['z_index'] as int,
    };
  }

  Future<void> save(ImageLayer layer, {DateTime? now}) async {
    final db = await _db;
    await db.insert(
      'image_layers',
      {
        'path': layer.path,
        'set_id': layer.setId,
        'z_index': layer.zIndex,
        'name': layer.name,
        'description': layer.description,
        'box_left': layer.box?.left,
        'box_top': layer.box?.top,
        'box_right': layer.box?.right,
        'box_bottom': layer.box?.bottom,
        'created_at': (now ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    layeredPaths.value = {...layeredPaths.value, layer.path: layer.zIndex};
  }

  /// The decomposition [path] belongs to, with every file that is still on
  /// disk; null when [path] is in none, or when nothing is left to stack
  /// (no layer above the base survives).
  Future<ImageLayerSet?> setFor(String path) async {
    final db = await _db;
    final own = await db.query('image_layers',
        columns: ['set_id'], where: 'path = ?', whereArgs: [path], limit: 1);
    if (own.isEmpty) return null;
    final setId = own.single['set_id'] as String;
    final rows = await db.query('image_layers',
        where: 'set_id = ?', whereArgs: [setId]);
    final layers = [
      for (final r in rows)
        if (File(r['path'] as String).existsSync()) _fromRow(r),
    ];
    final set = ImageLayerSet(setId, layers);
    return set.overlays.isEmpty ? null : set;
  }

  /// Carries rows along a rename or move of [from] to [to] — a file, or a
  /// directory whose files all move with it.
  ///
  /// Bookkeeping, never a reason for the move itself to fail: errors are
  /// swallowed. Answered from [layeredPaths] first, so the common case — a
  /// file no decomposition produced — never touches the database (and the
  /// file services' tests never open one).
  ///
  /// A move that overwrote [to] also retires [to]'s own row: the file it
  /// described is gone, and left alone the row would dress whatever now
  /// sits at that path as a layer (review 1).
  Future<void> move(String from, String to) async {
    if (from == to) return;
    final prefix = from.endsWith(p.separator) ? from : '$from${p.separator}';
    final known = layeredPaths.value;
    final overwrote = known.containsKey(to);
    final carries =
        known.keys.any((path) => path == from || path.startsWith(prefix));
    if (!overwrote && !carries) return;
    try {
      if (overwrote) await _forget(to);
      if (carries) await _move(from, to, prefix);
    } catch (e) {
      debugPrint('ImageLayerRepository.move($from → $to) failed: $e');
    }
  }

  /// Drops [path]'s row — for a copy that overwrote it, which has no
  /// source row to carry over. Bookkeeping like [move]: no database touch
  /// for a path the index does not know, errors swallowed.
  Future<void> forget(String path) async {
    if (!layeredPaths.value.containsKey(path)) return;
    try {
      await _forget(path);
    } catch (e) {
      debugPrint('ImageLayerRepository.forget($path) failed: $e');
    }
  }

  Future<void> _forget(String path) async {
    final db = await _db;
    await db.delete('image_layers', where: 'path = ?', whereArgs: [path]);
    layeredPaths.value = {...layeredPaths.value}..remove(path);
  }

  Future<void> _move(String from, String to, String prefix) async {
    final db = await _db;
    // substr rather than LIKE: a path may contain `%` or `_`.
    final changed = await db.rawUpdate(
      'UPDATE OR REPLACE image_layers SET path = CASE WHEN path = ? THEN ? '
      'ELSE ? || substr(path, ?) END '
      'WHERE path = ? OR substr(path, 1, ?) = ?',
      [
        from, to, //
        to.endsWith(p.separator) ? to : '$to${p.separator}', prefix.length + 1,
        from, prefix.length, prefix,
      ],
    );
    if (changed > 0) await loadPaths();
  }

  static ImageLayer _fromRow(Map<String, Object?> r) {
    final l = r['box_left'], t = r['box_top'];
    final rt = r['box_right'], b = r['box_bottom'];
    return ImageLayer(
      path: r['path'] as String,
      setId: r['set_id'] as String,
      zIndex: r['z_index'] as int,
      name: r['name'] as String?,
      description: r['description'] as String?,
      box: l is int && t is int && rt is int && b is int
          ? LayerBox(l, t, rt, b)
          : null,
    );
  }
}
