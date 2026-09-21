import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../models/token_usage.dart';
import '../../../models/usage_checkpoint.dart';
import '../database_service.dart';

class UsageRepository {
  UsageRepository({DatabaseService? db}) : _dbService = db ?? DatabaseService();

  final DatabaseService _dbService;

  Future<Database> get _db async => _dbService.database;

  Future<void> recordTokenUsage(TokenUsage usage) async {
    final db = await _db;
    await db.insert('token_usage', usage.toMap());
  }

  /// Re-prices the usage row recorded under [taskId] at [billing]; returns
  /// how many rows matched (0 for a row written before ids were durable).
  Future<int> updateSpecBilling(String taskId, UsageSpecBilling billing) async {
    final db = await _db;
    return db.update('token_usage', billing.toOutputMap(),
        where: 'task_id = ?', whereArgs: [taskId]);
  }

  /// Points every usage row and task row recorded against a key of [idMap]
  /// at its value — a channel merge folding one model into another, so the
  /// history follows the model rather than reading "deleted model".
  Future<void> remapModels(Map<int, int> idMap) async {
    if (idMap.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      for (final e in idMap.entries) {
        for (final table in const ['token_usage', 'tasks']) {
          await txn.update(table, {'model_pk': e.value},
              where: 'model_pk = ?', whereArgs: [e.key]);
        }
      }
    });
  }

  /// How many usage and task rows name one of [ids].
  Future<int> countModelRows(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return 0;
    final db = await _db;
    final marks = List.filled(list.length, '?').join(',');
    var n = 0;
    for (final table in const ['token_usage', 'tasks']) {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM $table WHERE model_pk IN ($marks)', list);
      n += rows.first['n'] as int? ?? 0;
    }
    return n;
  }

  Future<void> clearTokenUsage({String? modelId}) async {
    final db = await _db;
    if (modelId != null) {
      await db.delete('token_usage', where: 'model_id = ?', whereArgs: [modelId]);
    } else {
      await db.delete('token_usage');
    }
  }

  Future<List<TokenUsage>> getTokenUsage({
    List<String>? modelIds,
    DateTime? start,
    DateTime? end,
    int? limit,
    int? offset,
  }) async {
    final db = await _db;
    String where = '1=1';
    final List<dynamic> args = [];

    if (modelIds != null && modelIds.isNotEmpty) {
      where += " AND model_id IN (${modelIds.map((_) => '?').join(',')})";
      args.addAll(modelIds);
    }

    if (start != null) {
      where += ' AND timestamp >= ?';
      args.add(start.toIso8601String());
    }

    if (end != null) {
      where += ' AND timestamp <= ?';
      args.add(end.toIso8601String());
    }

    final rows = await db.query(
      'token_usage',
      where: where,
      whereArgs: args,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(TokenUsage.fromMap).toList();
  }

  Future<void> saveUsageCheckpoint(UsageCheckpoint checkpoint) async {
    final db = await _db;
    await db.insert('usage_checkpoints', checkpoint.toMap());
  }

  Future<UsageCheckpoint?> getLatestUsageCheckpoint() async {
    final db = await _db;
    final results = await db.query('usage_checkpoints', orderBy: 'timestamp DESC', limit: 1);
    if (results.isEmpty) return null;
    return UsageCheckpoint.fromMap(results.first);
  }
}
