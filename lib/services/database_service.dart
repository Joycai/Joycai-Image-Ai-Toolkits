import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_migrations.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String dbPath;
    
    // Migration: Check if DB exists in Documents (old location) and move it to Support (new location)
    // This applies primarily to macOS and Mobile where the previous implementation used Documents.
    final supportDir = await getApplicationSupportDirectory();
    final newPath = join(supportDir.path, 'joycai_workbench.db');
    
    final docsDir = await getApplicationDocumentsDirectory();
    final oldPath = join(docsDir.path, 'joycai_workbench.db');

    if (await File(oldPath).exists() && !await File(newPath).exists()) {
      try {
        if (!await supportDir.exists()) {
          await supportDir.create(recursive: true);
        }
        await File(oldPath).rename(newPath);
      } catch (e) {
        // Fallback: If migration fails, we might just start fresh or log it.
        // For now, we proceed.
      }
    }

    dbPath = newPath;
    
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 13, // Incremented for Prompt Tag CRUD
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      return await openDatabase(
        dbPath,
        version: 13,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  Future<String> getDatabasePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return supportDir.path;
  }

  Future<void> _onCreate(Database db, int version) async {
    await DatabaseMigration.onCreate(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await DatabaseMigration.migrate(db, oldVersion, newVersion);
  }

  // Task History Methods
  Future<void> saveTask(Map<String, dynamic> task) async {
    final db = await database;
    await db.insert('tasks', task, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getRecentTasks(int limit) async {
    final db = await database;
    return await db.query('tasks', orderBy: 'start_time DESC', limit: limit);
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  // Token Usage Methods
  Future<void> recordTokenUsage(Map<String, dynamic> usage) async {
    final db = await database;
    await db.insert('token_usage', usage);
  }

  Future<void> clearTokenUsage({String? modelId}) async {
    final db = await database;
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
  }) async {
    final db = await database;
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

    return await db.query('token_usage', where: where, whereArgs: args, orderBy: 'timestamp DESC');
  }

  // Prompts Methods
  Future<int> addPrompt(Map<String, dynamic> prompt) async {
    final db = await database;
    return await db.insert('prompts', prompt);
  }

  Future<void> updatePrompt(int id, Map<String, dynamic> prompt) async {
    final db = await database;
    await db.update('prompts', prompt, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePrompt(int id) async {
    final db = await database;
    await db.delete('prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPrompts() async {
    final db = await database;
    return await db.query('prompts', orderBy: 'sort_order ASC');
  }

  Future<void> updatePromptOrder(List<int> ids) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < ids.length; i++) {
      batch.update('prompts', {'sort_order': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
  }

  // LLM Models Methods
  Future<int> addModel(Map<String, dynamic> model) async {
    final db = await database;
    return await db.insert('llm_models', model);
  }

  Future<void> updateModel(int id, Map<String, dynamic> model) async {
    final db = await database;
    await db.update('llm_models', model, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateModelOrder(List<int> ids) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < ids.length; i++) {
      batch.update('llm_models', {'sort_order': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteModel(int id) async {
    final db = await database;
    await db.delete('llm_models', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getModels() async {
    final db = await database;
    return await db.query('llm_models', orderBy: 'sort_order ASC');
  }

  // Settings Methods
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return maps.isNotEmpty ? maps.first['value'] as String : null;
  }

  Future<void> resetAllSettings() async {
    final db = await database;
    await db.delete('settings');
    await db.delete('llm_models');
    await db.delete('source_directories');
    await db.delete('prompts');
    await db.delete('token_usage');
    await db.delete('tasks');
  }

  // Source Directories Methods
  Future<void> addSourceDirectory(String path) async {
    final db = await database;
    await db.insert('source_directories', {'path': path, 'is_selected': 1}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeSourceDirectory(String path) async {
    final db = await database;
    await db.delete('source_directories', where: 'path = ?', whereArgs: [path]);
  }

  Future<void> updateDirectorySelection(String path, bool isSelected) async {
    final db = await database;
    await db.update('source_directories', {'is_selected': isSelected ? 1 : 0}, where: 'path = ?', whereArgs: [path]);
  }

  Future<List<Map<String, dynamic>>> getSourceDirectories() async {
    final db = await database;
    return await db.query('source_directories');
  }

  // Fee Groups Methods
  Future<int> addFeeGroup(Map<String, dynamic> group) async {
    final db = await database;
    return await db.insert('fee_groups', group);
  }

  Future<void> updateFeeGroup(int id, Map<String, dynamic> group) async {
    final db = await database;
    await db.update('fee_groups', group, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteFeeGroup(int id) async {
    final db = await database;
    // Set associated models to NULL or a default group?
    // For now, let's just set them to NULL (no fee group)
    await db.update('llm_models', {'fee_group_id': null}, where: 'fee_group_id = ?', whereArgs: [id]);
    await db.delete('fee_groups', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getFeeGroups() async {
    final db = await database;
    return await db.query('fee_groups');
  }

  // LLM Channels Methods
  Future<int> addChannel(Map<String, dynamic> channel) async {
    final db = await database;
    return await db.insert('llm_channels', channel);
  }

  Future<void> updateChannel(int id, Map<String, dynamic> channel) async {
    final db = await database;
    await db.update('llm_channels', channel, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteChannel(int id) async {
    final db = await database;
    // Set associated models to NULL? or delete models? 
    // Requirement says user can delete channel. Usually we should handle orphaned models.
    await db.update('llm_models', {'channel_id': null}, where: 'channel_id = ?', whereArgs: [id]);
    await db.delete('llm_channels', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getChannels() async {
    final db = await database;
    return await db.query('llm_channels');
  }

  Future<Map<String, dynamic>?> getChannel(int id) async {
    final db = await database;
    final maps = await db.query('llm_channels', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? maps.first : null;
  }

  // Prompt Tags Methods
  Future<int> addPromptTag(Map<String, dynamic> tag) async {
    final db = await database;
    return await db.insert('prompt_tags', tag);
  }

  Future<void> updatePromptTag(int id, Map<String, dynamic> tag) async {
    final db = await database;
    await db.update('prompt_tags', tag, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePromptTag(int id) async {
    final db = await database;
    // Set associated prompts to "General" or null? 
    // Let's find "General" tag ID first.
    final general = await db.query('prompt_tags', where: 'name = ?', whereArgs: ['General'], limit: 1);
    int? generalId = general.isNotEmpty ? general.first['id'] as int : null;
    
    await db.update('prompts', {'tag_id': generalId}, where: 'tag_id = ?', whereArgs: [id]);
    await db.delete('prompt_tags', where: 'id = ? AND is_system = 0', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getPromptTags() async {
    final db = await database;
    return await db.query('prompt_tags');
  }
}
