import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

class TaskRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  Future<void> saveTask(Map<String, dynamic> task) async {
    final db = await _db;
    await db.insert('tasks', task, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// The newest [limit] tasks by creation time.
  ///
  /// Ordered by `created_at`, not `start_time`: a pending task has no start
  /// time, and under `start_time DESC` SQLite sorted those NULLs *last* — so
  /// the tasks still waiting were the first ones the cap dropped. The
  /// COALESCE covers rows a restored pre-v39 backup lands without the column
  /// filled, the same fallback `TaskItem.fromMap` applies.
  Future<List<Map<String, dynamic>>> getRecentTasks(int limit) async {
    final db = await _db;
    return await db.query(
      'tasks',
      orderBy: 'COALESCE(created_at, start_time, end_time) DESC',
      limit: limit,
    );
  }

  /// Tasks whose parameters carry the given assistant session id — the
  /// stored side of generation→prompt-version provenance.
  ///
  /// The LIKE over the parameters JSON is only a prefilter (it can match the
  /// id embedded in some other string); callers re-check the decoded
  /// parameters via `PromptProvenance.resultVersionsFromTasks`.
  ///
  /// Queried DESC and returned reversed to ascending: SQLite applies LIMIT
  /// after ORDER BY, so `ASC LIMIT` kept the *oldest* [limit] rows and dropped
  /// the most recent generations — exactly the ones on screen — once a
  /// long-lived session passed the cap. DESC keeps the newest within the cap;
  /// the reversal restores the ascending order the caller relies on, so later
  /// tasks still win map collisions in `resultVersionsFromTasks`.
  Future<List<Map<String, dynamic>>> getTasksForAssistantSession(
    String sessionId, {
    int limit = 500,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'tasks',
      where: 'parameters LIKE ?',
      whereArgs: ['%"assistantSessionId":"$sessionId"%'],
      orderBy: 'start_time DESC',
      limit: limit,
    );
    return rows.reversed.toList();
  }

  Future<void> deleteTask(String id) async {
    final db = await _db;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cleanupStuckTasks() async {
    final db = await _db;
    await db.update(
      'tasks', 
      {'status': 'failed'}, 
      where: 'status = ?', 
      whereArgs: ['processing']
    );
  }

  Future<List<double>> getTaskDurations(int modelDbId, int limit) async {
    final db = await _db;
    final results = await db.query(
      'tasks',
      columns: ['start_time', 'end_time'],
      where: 'model_pk = ? AND status = "completed" AND start_time IS NOT NULL AND end_time IS NOT NULL'.replaceAll('"', "'"),
      whereArgs: [modelDbId],
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
