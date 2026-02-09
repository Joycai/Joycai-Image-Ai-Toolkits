import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../database_service.dart';

class PromptRepository {
  final DatabaseService _dbService = DatabaseService();

  Future<Database> get _db async => await _dbService.database;

  Future<int> addPrompt(Prompt prompt, {List<int>? tagIds}) async {
    final db = await _db;
    return await db.transaction((txn) async {
      // Use includeId: false because it's AUTOINCREMENT
      final id = await txn.insert('prompts', prompt.toMap(includeId: false));
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

  Future<void> updatePrompt(int id, Prompt prompt, {List<int>? tagIds}) async {
    final db = await _db;
    await db.transaction((txn) async {
      // CRITICAL: Use includeId: false to avoid updating the Primary Key to NULL
      await txn.update('prompts', prompt.toMap(includeId: false), where: 'id = ?', whereArgs: [id]);
      
      if (tagIds != null) {
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

  Future<List<Prompt>> getPrompts() async {
    final db = await _db;
    
    final results = await db.rawQuery('''
      SELECT p.*, 
             json_group_array(
               json_object(
                 'id', t.id,
                 'name', t.name,
                 'color', t.color,
                 'is_system', t.is_system
               )
             ) as tags_json
      FROM prompts p
      LEFT JOIN prompt_tag_refs r ON p.id = r.prompt_id
      LEFT JOIN prompt_tags t ON r.tag_id = t.id
      GROUP BY p.id
      ORDER BY p.sort_order ASC
    ''');

    return results.map((row) {
      final data = Map<String, dynamic>.from(row);
      
      if (data['tags_json'] != null) {
        try {
          final String jsonStr = data['tags_json'] as String;
          final List<dynamic> parsedTags = jsonDecode(jsonStr);
          data['tags'] = parsedTags.where((t) => t != null && t['id'] != null).toList();
        } catch (e) {
          data['tags'] = [];
        }
      } else {
        data['tags'] = [];
      }
      
      return Prompt.fromMap(data);
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

  Future<int> addPromptTag(PromptTag tag) async {
    final db = await _db;
    return await db.insert('prompt_tags', tag.toMap(includeId: false));
  }

  Future<void> updatePromptTag(int id, PromptTag tag) async {
    final db = await _db;
    await db.update('prompt_tags', tag.toMap(includeId: false), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePromptTag(int id) async {
    final db = await _db;
    await db.delete('prompt_tags', where: 'id = ? AND is_system = 0', whereArgs: [id]);
  }

  Future<List<PromptTag>> getPromptTags() async {
    final db = await _db;
    final maps = await db.query('prompt_tags');
    return maps.map((m) => PromptTag.fromMap(m)).toList();
  }

  // System Prompts Methods
  Future<int> addSystemPrompt(SystemPrompt prompt) async {
    final db = await _db;
    return await db.insert('system_prompts', prompt.toMap(includeId: false));
  }

  Future<void> updateSystemPrompt(int id, SystemPrompt prompt) async {
    final db = await _db;
    await db.update('system_prompts', prompt.toMap(includeId: false), where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSystemPrompt(int id) async {
    final db = await _db;
    await db.delete('system_prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SystemPrompt>> getSystemPrompts({String? type}) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps;
    if (type != null) {
      maps = await db.query('system_prompts', where: 'type = ?', whereArgs: [type]);
    } else {
      maps = await db.query('system_prompts');
    }
    return maps.map((m) => SystemPrompt.fromMap(m)).toList();
  }
}