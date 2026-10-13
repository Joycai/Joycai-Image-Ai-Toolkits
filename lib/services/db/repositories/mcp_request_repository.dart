import '../../../models/task_item.dart';
import '../database_service.dart';

/// Local replay protection survives removal of the corresponding history row.
/// Records live until the application database is removed; never exported.
class McpRequestRepository {
  McpRequestRepository({DatabaseService? db}) : _db = db ?? DatabaseService();
  final DatabaseService _db;

  Future<Map<String, Object?>?> find(String key) async {
    final rows = await (await _db.database).query(
      'mcp_requests',
      where: 'request_key = ?',
      whereArgs: [key],
    );
    return rows.firstOrNull;
  }

  Future<void> insert(String key, String digest, TaskItem task) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert('mcp_requests', {'request_key': key, 'digest': digest, 'task_id': task.id});
      await txn.insert('tasks', task.toMap());
    });
  }
}
