import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

class UsageRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  Future<void> recordTokenUsage(Map<String, dynamic> usage) async {
    final db = await _db;
    await db.insert('token_usage', usage);
  }

  Future<void> clearTokenUsage({String? modelId}) async {
    final db = await _db;
    if (modelId != null) {
      await db.delete('token_usage', where: 'model_id = ?', whereArgs: [modelId]);
    } else {
      await db.delete('token_usage');
    }
  }

  Future<List<Map<String, dynamic>>> getTokenUsage({
    List<String>? modelIds,
    DateTime? start,
    DateTime? end,
    int? limit,
    int? offset,
  }) async {
    final db = await _db;
    String where = "1=1";
    List<dynamic> args = [];

    if (modelIds != null && modelIds.isNotEmpty) {
      where += " AND model_id IN (${modelIds.map((_) => '?').join(',')})";
      args.addAll(modelIds);
    }

    if (start != null) {
      where += " AND timestamp >= ?";
      args.add(start.toIso8601String());
    }

    if (end != null) {
      where += " AND timestamp <= ?";
      args.add(end.toIso8601String());
    }

    return await db.query(
      'token_usage', 
      where: where, 
      whereArgs: args, 
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> saveUsageCheckpoint(Map<String, dynamic> checkpoint) async {
    final db = await _db;
    await db.insert('usage_checkpoints', checkpoint);
  }

  Future<Map<String, dynamic>?> getLatestUsageCheckpoint() async {
    final db = await _db;
    final results = await db.query('usage_checkpoints', orderBy: 'timestamp DESC', limit: 1);
    if (results.isEmpty) return null;
    return results.first;
  }
}
