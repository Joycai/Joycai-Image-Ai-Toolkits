import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

class PromptRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  Future<int> addPrompt(Map<String, dynamic> prompt) async {
    final db = await _db;
    return await db.insert('prompts', prompt);
  }

  Future<void> updatePrompt(int id, Map<String, dynamic> prompt) async {
    final db = await _db;
    await db.update('prompts', prompt, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePrompt(int id) async {
    final db = await _db;
    await db.delete('prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPrompts() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT p.*, t.name as tag_name, t.color as tag_color, t.is_system as tag_is_system
      FROM prompts p
      LEFT JOIN prompt_tags t ON p.tag_id = t.id
      ORDER BY p.sort_order ASC
    ''');
  }

  Future<void> updatePromptOrder(List<int> ids) async {
    final db = await _db;
    final batch = db.batch();
    for (int i = 0; i < ids.length; i++) {
      batch.update('prompts', {'sort_order': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<int> addPromptTag(Map<String, dynamic> tag) async {
    final db = await _db;
    return await db.insert('prompt_tags', tag);
  }

  Future<void> updatePromptTag(int id, Map<String, dynamic> tag) async {
    final db = await _db;
    await db.update('prompt_tags', tag, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePromptTag(int id) async {
    final db = await _db;
    final general = await db.query('prompt_tags', where: 'name = ?', whereArgs: ['General'], limit: 1);
    int? generalId = general.isNotEmpty ? general.first['id'] as int : null;
    
    await db.update('prompts', {'tag_id': generalId}, where: 'tag_id = ?', whereArgs: [id]);
    await db.delete('prompt_tags', where: 'id = ? AND is_system = 0', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPromptTags() async {
    final db = await _db;
    return await db.query('prompt_tags');
  }

  // System Prompts Methods
  Future<int> addSystemPrompt(Map<String, dynamic> prompt) async {
    final db = await _db;
    return await db.insert('system_prompts', prompt);
  }

  Future<void> updateSystemPrompt(int id, Map<String, dynamic> prompt) async {
    final db = await _db;
    await db.update('system_prompts', prompt, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSystemPrompt(int id) async {
    final db = await _db;
    await db.delete('system_prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getSystemPrompts({String? type}) async {
    final db = await _db;
    if (type != null) {
      return await db.query('system_prompts', where: 'type = ?', whereArgs: [type]);
    }
    return await db.query('system_prompts');
  }
}
