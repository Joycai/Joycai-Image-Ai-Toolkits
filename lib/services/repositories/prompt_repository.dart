import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database_service.dart';

class PromptRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  Future<int> addPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    final db = await _db;
    return await db.transaction((txn) async {
      final id = await txn.insert('prompts', prompt);
      if (tagIds != null && tagIds.isNotEmpty) {
        for (var tagId in tagIds) {
          await txn.insert('prompt_tag_refs', {
            'prompt_id': id,
            'tag_id': tagId,
          });
        }
      }
      return id;
    });
  }

  Future<void> updatePrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('prompts', prompt, where: 'id = ?', whereArgs: [id]);
      
      if (tagIds != null) {
        // Sync tags: remove old, add new
        await txn.delete('prompt_tag_refs', where: 'prompt_id = ?', whereArgs: [id]);
        for (var tagId in tagIds) {
          await txn.insert('prompt_tag_refs', {
            'prompt_id': id,
            'tag_id': tagId,
          });
        }
      }
    });
  }

  Future<void> deletePrompt(int id) async {
    final db = await _db;
    await db.delete('prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPrompts() async {
    final db = await _db;
    // Get all prompts
    final prompts = await db.query('prompts', orderBy: 'sort_order ASC');
    
    // Get all tag assignments
    final refs = await db.rawQuery('''
      SELECT r.prompt_id, t.*
      FROM prompt_tag_refs r
      JOIN prompt_tags t ON r.tag_id = t.id
    ''');

    // Group tags by prompt_id
    final Map<int, List<Map<String, dynamic>>> promptTagsMap = {};
    for (var ref in refs) {
      final pid = ref['prompt_id'] as int;
      promptTagsMap[pid] ??= [];
      promptTagsMap[pid]!.add(ref);
    }

    // Combine
    return prompts.map((p) {
      final mutable = Map<String, dynamic>.from(p);
      final pid = p['id'] as int;
      mutable['tags'] = promptTagsMap[pid] ?? [];
      return mutable;
    }).toList();
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
    // References in prompt_tag_refs will be deleted by CASCADE
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