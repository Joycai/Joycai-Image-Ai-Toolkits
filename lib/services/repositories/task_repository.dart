import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

class TaskRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  Future<void> saveTask(Map<String, dynamic> task) async {
    final db = await _db;
    await db.insert('tasks', task, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getRecentTasks(int limit) async {
    final db = await _db;
    return await db.query('tasks', orderBy: 'start_time DESC', limit: limit);
  }

  Future<void> deleteTask(String id) async {
    final db = await _db;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<double>> getTaskDurations(int modelPk, int limit) async {
    final db = await _db;
    final results = await db.query(
      'tasks',
      columns: ['start_time', 'end_time'],
      where: 'model_pk = ? AND status = "completed" AND start_time IS NOT NULL AND end_time IS NOT NULL'.replaceAll('"', "'"),
      whereArgs: [modelPk],
      orderBy: 'end_time DESC',
      limit: limit,
    );

    return results.map((r) {
      final start = DateTime.parse(r['start_time'] as String);
      final end = DateTime.parse(r['end_time'] as String);
      return end.difference(start).inMilliseconds.toDouble();
    }).toList();
  }
}
