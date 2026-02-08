import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/app_paths.dart';
import 'database_migrations.dart';
import 'repositories/model_repository.dart';
import 'repositories/prompt_repository.dart';
import 'repositories/task_repository.dart';
import 'repositories/usage_repository.dart';

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
    
    final dataDir = await AppPaths.getDataDirectory();
    final newPath = join(dataDir, 'joycai_workbench.db');
    
    // Legacy migration check (Only for non-portable mode or first transition)
    if (!await AppPaths.isPortableMode()) {
      final docsDir = await getApplicationDocumentsDirectory();
      final oldPath = join(docsDir.path, 'joycai_workbench.db');

      if (await File(oldPath).exists() && !await File(newPath).exists()) {
        try {
          final dir = Directory(dataDir);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          await File(oldPath).rename(newPath);
        } catch (_) {}
      }
    }

    dbPath = newPath;
    
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 19, // Incremented for Multi-tag support
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      return await openDatabase(
        dbPath,
        version: 19,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  Future<String> getDatabasePath() async {
    return await AppPaths.getDataDirectory();
  }

  Future<void> _onCreate(Database db, int version) async {
    await DatabaseMigration.onCreate(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await DatabaseMigration.migrate(db, oldVersion, newVersion);
  }

  // Task History Methods
  Future<void> saveTask(Map<String, dynamic> task) => TaskRepository().saveTask(task);
  Future<List<Map<String, dynamic>>> getRecentTasks(int limit) => TaskRepository().getRecentTasks(limit);
  Future<void> deleteTask(String id) => TaskRepository().deleteTask(id);
  Future<List<double>> getTaskDurations(int modelPk, int limit) => TaskRepository().getTaskDurations(modelPk, limit);

  // Token Usage Methods
  Future<void> recordTokenUsage(Map<String, dynamic> usage) => UsageRepository().recordTokenUsage(usage);
  Future<void> clearTokenUsage({String? modelId}) => UsageRepository().clearTokenUsage(modelId: modelId);
  Future<List<Map<String, dynamic>>> getTokenUsage({List<String>? modelIds, DateTime? start, DateTime? end}) 
      => UsageRepository().getTokenUsage(modelIds: modelIds, start: start, end: end);

  // Prompts Methods
  Future<int> addPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) => PromptRepository().addPrompt(prompt, tagIds: tagIds);
  Future<void> updatePrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) => PromptRepository().updatePrompt(id, prompt, tagIds: tagIds);
  Future<void> deletePrompt(int id) => PromptRepository().deletePrompt(id);
  Future<List<Map<String, dynamic>>> getPrompts() => PromptRepository().getPrompts();
  Future<void> updatePromptOrder(List<int> ids) => PromptRepository().updatePromptOrder(ids);

  // LLM Models Methods
  Future<int> addModel(Map<String, dynamic> model) => ModelRepository().addModel(model);
  Future<void> updateModel(int id, Map<String, dynamic> model) => ModelRepository().updateModel(id, model);
  Future<void> updateModelOrder(List<int> ids) => ModelRepository().updateModelOrder(ids);
  Future<void> deleteModel(int id) => ModelRepository().deleteModel(id);
  Future<List<Map<String, dynamic>>> getModels() => ModelRepository().getModels();
  Future<void> updateModelEstimation(int modelPk, double mean, double sd, int tasksSinceUpdate) 
      => ModelRepository().updateModelEstimation(modelPk, mean, sd, tasksSinceUpdate);

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
    await db.delete('downloader_cookies');
  }

  // Downloader Cookies History
  Future<void> saveDownloaderCookie(String host, String cookies) async {
    final db = await database;
    await db.insert('downloader_cookies', {
      'host': host,
      'cookies': cookies,
      'last_used': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    
    // Limit to last 5
    final all = await db.query('downloader_cookies', orderBy: 'last_used DESC');
    if (all.length > 5) {
      final toDelete = all.sublist(5);
      for (var row in toDelete) {
        await db.delete('downloader_cookies', where: 'host = ?', whereArgs: [row['host']]);
      }
    }
  }

  Future<List<Map<String, dynamic>>> getDownloaderCookies() async {
    final db = await database;
    return await db.query('downloader_cookies', orderBy: 'last_used DESC');
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
  Future<int> addFeeGroup(Map<String, dynamic> group) => ModelRepository().addFeeGroup(group);
  Future<void> updateFeeGroup(int id, Map<String, dynamic> group) => ModelRepository().updateFeeGroup(id, group);
  Future<void> deleteFeeGroup(int id) => ModelRepository().deleteFeeGroup(id);
  Future<List<Map<String, dynamic>>> getFeeGroups() => ModelRepository().getFeeGroups();

  // LLM Channels Methods
  Future<int> addChannel(Map<String, dynamic> channel) => ModelRepository().addChannel(channel);
  Future<void> updateChannel(int id, Map<String, dynamic> channel) => ModelRepository().updateChannel(id, channel);
  Future<void> deleteChannel(int id) => ModelRepository().deleteChannel(id);
  Future<List<Map<String, dynamic>>> getChannels() => ModelRepository().getChannels();
  Future<Map<String, dynamic>?> getChannel(int id) => ModelRepository().getChannel(id);

  // Prompt Tags Methods
  Future<int> addPromptTag(Map<String, dynamic> tag) => PromptRepository().addPromptTag(tag);
  Future<void> updatePromptTag(int id, Map<String, dynamic> tag) => PromptRepository().updatePromptTag(id, tag);
  Future<void> deletePromptTag(int id) => PromptRepository().deletePromptTag(id);
  Future<List<Map<String, dynamic>>> getPromptTags() => PromptRepository().getPromptTags();

  // System Prompts Methods
  Future<int> addSystemPrompt(Map<String, dynamic> prompt) => PromptRepository().addSystemPrompt(prompt);
  Future<void> updateSystemPrompt(int id, Map<String, dynamic> prompt) => PromptRepository().updateSystemPrompt(id, prompt);
  Future<void> deleteSystemPrompt(int id) => PromptRepository().deleteSystemPrompt(id);
  Future<List<Map<String, dynamic>>> getSystemPrompts({String? type}) => PromptRepository().getSystemPrompts(type: type);

  // Standalone Prompt Data
  Future<Map<String, dynamic>> getPromptDataRaw() async {
    return {
      'tags': await getPromptTags(),
      'user_prompts': await getPrompts(),
      'system_prompts': await getSystemPrompts(),
    };
  }

  // Backup & Restore (Now with optional prompt inclusion)
  Future<Map<String, dynamic>> getAllDataRaw({bool includePrompts = false}) async {
    final db = await database;
    final Map<String, dynamic> data = {
      'settings': await db.query('settings'),
      'llm_channels': await db.query('llm_channels'),
      'llm_models': await db.query('llm_models'),
      'fee_groups': await db.query('fee_groups'),
      'source_directories': await db.query('source_directories'),
    };

    if (includePrompts) {
      data.addAll(await getPromptDataRaw());
    }

    return data;
  }

  Future<void> clearAllData(DatabaseExecutor txn, {bool includePrompts = false}) async {
    await txn.delete('settings');
    await txn.delete('llm_channels');
    await txn.delete('llm_models');
    await txn.delete('fee_groups');
    await txn.delete('source_directories');

    if (includePrompts) {
      await txn.delete('prompt_tags');
      await txn.delete('prompts');
      await txn.delete('system_prompts');
      await txn.delete('prompt_tag_refs');
    }
  }

  Future<void> restoreBackup(Map<String, dynamic> data) async {
    final db = await database;
    final bool includePrompts = data.containsKey('prompts') || data.containsKey('user_prompts');

    await db.transaction((txn) async {
      await clearAllData(txn, includePrompts: includePrompts);

      final channelIdMap = await _importChannels(txn, data['llm_channels']);
      final feeGroupIdMap = await _importFeeGroups(txn, data['fee_groups']);
      await _importModels(txn, data['llm_models'], channelIdMap, feeGroupIdMap);
      
      if (includePrompts) {
        final tagIdMap = await _importPromptTags(txn, data['prompt_tags'] ?? data['tags']);
        await _importPrompts(txn, data['prompts'] ?? data['user_prompts'], tagIdMap);
        await _importSimpleTable(txn, 'system_prompts', data['system_prompts']);
      }
      
      await _importSimpleTable(txn, 'settings', data['settings']);
      await _importSimpleTable(txn, 'source_directories', data['source_directories']);
    });
  }

  Future<void> _importSimpleTable(DatabaseExecutor txn, String table, List<dynamic>? rows) async {
    if (rows == null || rows.isEmpty) return;
    final batch = txn.batch();
    for (var row in rows) {
      batch.insert(table, row as Map<String, dynamic>);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, int>> _importChannels(DatabaseExecutor txn, List<dynamic>? rows) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var c in rows) {
      final oldId = c['id'] as int;
      final Map<String, dynamic> row = Map.from(c)..remove('id');
      final newId = await txn.insert('llm_channels', row);
      idMap[oldId] = newId;
    }
    return idMap;
  }

  Future<Map<int, int>> _importFeeGroups(DatabaseExecutor txn, List<dynamic>? rows) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var g in rows) {
      final oldId = g['id'] as int;
      final Map<String, dynamic> row = Map.from(g)..remove('id');
      final newId = await txn.insert('fee_groups', row);
      idMap[oldId] = newId;
    }
    return idMap;
  }

  Future<void> _importModels(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> channelIdMap, Map<int, int> feeGroupIdMap) async {
    if (rows == null) return;
    final batch = txn.batch();
    for (var m in rows) {
      final Map<String, dynamic> row = Map.from(m)..remove('id');
      if (row['channel_id'] != null) row['channel_id'] = channelIdMap[row['channel_id']];
      if (row['fee_group_id'] != null) row['fee_group_id'] = feeGroupIdMap[row['fee_group_id']];
      batch.insert('llm_models', row);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, int>> _importPromptTags(DatabaseExecutor txn, List<dynamic>? rows) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var t in rows) {
      final oldId = t['id'] as int;
      final Map<String, dynamic> row = Map.from(t)..remove('id');
      try {
        final newId = await txn.insert('prompt_tags', row);
        idMap[oldId] = newId;
      } catch (e) {
        final existing = await txn.query('prompt_tags', where: 'name = ?', whereArgs: [row['name']]);
        if (existing.isNotEmpty) {
          idMap[oldId] = existing.first['id'] as int;
        }
      }
    }
    return idMap;
  }

  Future<void> _importPrompts(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> tagIdMap) async {
    if (rows == null) return;
    for (var p in rows) {
      final Map<String, dynamic> row = Map.from(p)..remove('id');
      final originalTagId = row['tag_id'] as int?;
      
      final List<dynamic>? tagsFromData = row['tags'];
      row.remove('tags');
      row.remove('tag_name'); 
      row.remove('tag_color');
      row.remove('tag_is_system');

      final newPromptId = await txn.insert('prompts', row);

      if (tagsFromData != null) {
        for (var t in tagsFromData) {
          final oldTagId = t['id'] as int;
          final newTagId = tagIdMap[oldTagId];
          if (newTagId != null) {
            await txn.insert('prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
          }
        }
      } else if (originalTagId != null) {
        final newTagId = tagIdMap[originalTagId];
        if (newTagId != null) {
          await txn.insert('prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
        }
      }
    }
  }
}