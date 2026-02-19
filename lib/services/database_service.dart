import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/app_paths.dart';
import '../models/llm_channel.dart';
import '../models/llm_model.dart';
import '../models/pricing_group.dart';
import '../models/prompt.dart';
import '../models/tag.dart';
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
    await syncPresets();
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
          version: 24,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      // On macOS, iOS, and Android, use standard sqflite (non-FFI)
      // This avoids the 'native_assets' Null check operator bug on Flutter 3.38+ macOS Debug
      return await openDatabase(
        dbPath,
        version: 24,
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

  /// Synchronize preset prompts from asset files into the database.
  /// This checks for missing presets and inserts them if they don't exist by title.
  Future<void> syncPresets() async {
    final db = await database;
    
    // 1. Sync System Prompts
    try {
      final String systemJsonString = await rootBundle.loadString('assets/presets/prompts/system_prompts.json');
      final List<dynamic> systemPresets = jsonDecode(systemJsonString);
      
      for (var preset in systemPresets) {
        final existing = await db.query(
          'system_prompts', 
          where: 'title = ? AND type = ?', 
          whereArgs: [preset['title'], preset['type']]
        );
        if (existing.isEmpty) {
          await db.insert('system_prompts', preset);
        }
      }
    } catch (e) {
      // ignore
    }

    // 2. Sync User Prompts
    try {
      final String userJsonString = await rootBundle.loadString('assets/presets/prompts/user_prompts.json');
      final List<dynamic> userPresets = jsonDecode(userJsonString);
      
      for (var preset in userPresets) {
        final existing = await db.query(
          'prompts', 
          where: 'title = ?', 
          whereArgs: [preset['title']]
        );
        if (existing.isEmpty) {
          await db.insert('prompts', preset);
        }
      }
    } catch (e) {
      // ignore
    }
  }

  // Task History Methods
  Future<void> saveTask(Map<String, dynamic> task) => TaskRepository().saveTask(task);
  Future<List<Map<String, dynamic>>> getRecentTasks(int limit) => TaskRepository().getRecentTasks(limit);
  Future<void> deleteTask(String id) => TaskRepository().deleteTask(id);
  Future<void> cleanupStuckTasks() => TaskRepository().cleanupStuckTasks();
  Future<List<double>> getTaskDurations(int modelDbId, int limit) => TaskRepository().getTaskDurations(modelDbId, limit);

  // Token Usage Methods
  Future<void> recordTokenUsage(Map<String, dynamic> usage) => UsageRepository().recordTokenUsage(usage);
  Future<void> clearTokenUsage({String? modelId}) => UsageRepository().clearTokenUsage(modelId: modelId);
  Future<List<Map<String, dynamic>>> getTokenUsage({List<String>? modelIds, DateTime? start, DateTime? end, int? limit, int? offset}) 
      => UsageRepository().getTokenUsage(modelIds: modelIds, start: start, end: end, limit: limit, offset: offset);

  Future<void> saveUsageCheckpoint(Map<String, dynamic> checkpoint) => UsageRepository().saveUsageCheckpoint(checkpoint);
  Future<Map<String, dynamic>?> getLatestUsageCheckpoint() => UsageRepository().getLatestUsageCheckpoint();

  // --- MODEL BASED METHODS ---

  // Prompts Methods
  Future<int> addPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) => PromptRepository().addPrompt(Prompt.fromMap(prompt), tagIds: tagIds);
  Future<void> updatePrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) => PromptRepository().updatePrompt(id, Prompt.fromMap(prompt), tagIds: tagIds);
  Future<void> deletePrompt(int id) => PromptRepository().deletePrompt(id);
  Future<List<Prompt>> getPrompts() => PromptRepository().getPrompts();
  Future<void> updatePromptOrder(List<int> ids) => PromptRepository().updatePromptOrder(ids);

  // LLM Models Methods
  Future<int> addModel(Map<String, dynamic> model) => ModelRepository().addModel(LLMModel.fromMap(model));
  Future<void> updateModel(int id, Map<String, dynamic> model) => ModelRepository().updateModel(id, LLMModel.fromMap(model));
  Future<void> updateModelOrder(List<int> ids) => ModelRepository().updateModelOrder(ids);
  Future<void> deleteModel(int id) => ModelRepository().deleteModel(id);
  Future<List<LLMModel>> getModels() => ModelRepository().getModels();
  Future<void> updateModelEstimation(int modelDbId, double mean, double sd, int tasksSinceUpdate) 
      => ModelRepository().updateModelEstimation(modelDbId, mean, sd, tasksSinceUpdate);

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
    await db.transaction((txn) async {
      await clearAllData(txn, includePrompts: true);
    });
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

  // Pricing Groups Methods
  Future<int> addPricingGroup(Map<String, dynamic> group) => ModelRepository().addPricingGroup(PricingGroup.fromMap(group));
  Future<void> updatePricingGroup(int id, Map<String, dynamic> group) => ModelRepository().updatePricingGroup(id, PricingGroup.fromMap(group));
  Future<void> deletePricingGroup(int id) => ModelRepository().deletePricingGroup(id);
  Future<List<PricingGroup>> getPricingGroups() => ModelRepository().getPricingGroups();

  // LLM Channels Methods
  Future<int> addChannel(Map<String, dynamic> channel) => ModelRepository().addChannel(LLMChannel.fromMap(channel));
  Future<void> updateChannel(int id, Map<String, dynamic> channel) => ModelRepository().updateChannel(id, LLMChannel.fromMap(channel));
  Future<void> deleteChannel(int id) => ModelRepository().deleteChannel(id);
  Future<List<LLMChannel>> getChannels() => ModelRepository().getChannels();
  Future<LLMChannel?> getChannel(int id) => ModelRepository().getChannel(id);

  // Prompt Tags Methods
  Future<int> addPromptTag(Map<String, dynamic> tag) => PromptRepository().addPromptTag(PromptTag.fromMap(tag));
  Future<void> updatePromptTag(int id, Map<String, dynamic> tag) => PromptRepository().updatePromptTag(id, PromptTag.fromMap(tag));
  Future<void> deletePromptTag(int id) => PromptRepository().deletePromptTag(id);
  Future<List<PromptTag>> getPromptTags() => PromptRepository().getPromptTags();
  Future<void> updateTagOrder(List<int> ids) => PromptRepository().updateTagOrder(ids);

  // System Prompts Methods
  Future<int> addSystemPrompt(Map<String, dynamic> prompt, {List<int>? tagIds}) => PromptRepository().addSystemPrompt(SystemPrompt.fromMap(prompt), tagIds: tagIds);
  Future<void> updateSystemPrompt(int id, Map<String, dynamic> prompt, {List<int>? tagIds}) => PromptRepository().updateSystemPrompt(id, SystemPrompt.fromMap(prompt), tagIds: tagIds);
  Future<void> deleteSystemPrompt(int id) => PromptRepository().deleteSystemPrompt(id);
  Future<List<SystemPrompt>> getSystemPrompts({String? type}) => PromptRepository().getSystemPrompts(type: type);
  Future<void> updateSystemPromptOrder(List<int> ids) => PromptRepository().updateSystemPromptOrder(ids);

  // Standalone Prompt Data
  Future<Map<String, dynamic>> getPromptDataRaw() async {
    return {
      'tags': (await getPromptTags()).map((t) => t.toMap()).toList(),
      'user_prompts': (await getPrompts()).map((p) => {
        ...p.toMap(),
        'tags': p.tags.map((t) => t.toMap()).toList()
      }).toList(),
      'system_prompts': (await getSystemPrompts()).map((p) => {
        ...p.toMap(),
        'tags': p.tags.map((t) => t.toMap()).toList()
      }).toList(),
    };
  }

  // Backup & Restore (Now with optional prompt inclusion)
  Future<Map<String, dynamic>> getAllDataRaw({
    bool includePrompts = true, 
    bool includeUsage = true,
    bool includeDirectories = true,
  }) async {
    final db = await database;
    
    // Filter settings if directories are excluded
    final settingsRows = await db.query('settings');
    var filteredSettings = settingsRows;
    if (!includeDirectories) {
      final dirKeys = {'output_directory', 'browser_source_directories', 'browser_active_directories'};
      filteredSettings = settingsRows.where((row) => !dirKeys.contains(row['key'])).toList();
    }

    final Map<String, dynamic> data = {
      'settings': filteredSettings,
      'llm_channels': await db.query('llm_channels'),
      'llm_models': await db.query('llm_models'),
      'fee_groups': await db.query('fee_groups'),
      'downloader_cookies': await db.query('downloader_cookies'),
    };

    if (includeUsage) {
      data['token_usage'] = await db.query('token_usage');
    }

    if (includeDirectories) {
      data['source_directories'] = await db.query('source_directories');
    }

    if (includePrompts) {
      data.addAll(await getPromptDataRaw());
    }

    return data;
  }

  Future<void> clearAllData(DatabaseExecutor txn, {
    bool includePrompts = true, 
    bool includeUsage = true,
    bool includeDirectories = true,
  }) async {
    await txn.delete('settings');
    await txn.delete('llm_channels');
    await txn.delete('llm_models');
    await txn.delete('fee_groups');
    await txn.delete('tasks');
    await txn.delete('downloader_cookies');

    if (includeUsage) {
      await txn.delete('token_usage');
    }

    if (includeDirectories) {
      await txn.delete('source_directories');
    }

    if (includePrompts) {
      await txn.delete('prompts');
      await txn.delete('system_prompts');
      await txn.delete('prompt_tag_refs');
      await txn.delete('system_prompt_tag_refs');
      await txn.delete('prompt_tags');
    }
  }

  Future<void> restoreBackup(Map<String, dynamic> data, {
    bool includePrompts = true, 
    bool includeUsage = true, 
    bool includeDirectories = true,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      await clearAllData(txn, 
        includePrompts: includePrompts, 
        includeUsage: includeUsage, 
        includeDirectories: includeDirectories,
      );

      final channelIdMap = await _importChannels(txn, data['llm_channels']);
      final pricingGroupIdMap = await _importPricingGroups(txn, data['fee_groups']);
      final modelIdMap = await _importModels(txn, data['llm_models'], channelIdMap, pricingGroupIdMap);
      
      if (data['downloader_cookies'] != null) {
        await _importSimpleTable(txn, 'downloader_cookies', data['downloader_cookies']);
      }

      if (includeUsage && data['token_usage'] != null) {
        await _importTokenUsage(txn, data['token_usage'], modelIdMap);
      }

      if (includePrompts) {
        final tagIdMap = await _importPromptTags(txn, data['prompt_tags'] ?? data['tags']);
        await _importPrompts(txn, data['prompts'] ?? data['user_prompts'], tagIdMap);
        await _importSystemPrompts(txn, data['system_prompts'], tagIdMap);
      }
      
      if (data['settings'] != null) {
        final List<dynamic> settingsRows = data['settings'];
        var filteredSettings = settingsRows;
        if (!includeDirectories) {
          final dirKeys = {'output_directory', 'browser_source_directories', 'browser_active_directories'};
          filteredSettings = settingsRows.where((row) => !dirKeys.contains(row['key'])).toList();
        }
        await _importSimpleTable(txn, 'settings', filteredSettings);
      }

      if (includeDirectories && data['source_directories'] != null) {
        await _importSimpleTable(txn, 'source_directories', data['source_directories']);
      }
    });
  }

  Future<void> importPromptData(Map<String, dynamic> data, {bool replace = false}) async {
    final db = await database;
    await db.transaction((txn) async {
      if (replace) {
        await txn.delete('prompts');
        await txn.delete('prompt_tag_refs');
        await txn.delete('system_prompts');
        await txn.delete('prompt_tags'); 
      }

      // Import Tags first to get new IDs
      final Map<int, int> tagIdMap = {};
      if (data['tags'] != null) {
        for (var t in data['tags']) {
          final oldId = t['id'] as int;
          final Map<String, dynamic> row = Map.from(t)..remove('id');
          // Check if tag exists by name
          final existing = await txn.query('prompt_tags', where: 'name = ?', whereArgs: [row['name']]);
          if (existing.isNotEmpty) {
            tagIdMap[oldId] = existing.first['id'] as int;
          } else {
            final newId = await txn.insert('prompt_tags', row);
            tagIdMap[oldId] = newId;
          }
        }
      }

      // Import User Prompts
      if (data['user_prompts'] != null) {
        for (var p in data['user_prompts']) {
          final Map<String, dynamic> row = Map.from(p)..remove('id');
          final List<dynamic>? tags = row['tags'];
          row.remove('tags');
          row.remove('tag_name'); 
          row.remove('tag_color');
          row.remove('tag_is_system');
          row.remove('tag_id');

          final newPromptId = await txn.insert('prompts', row);
          if (tags != null) {
            for (var t in tags) {
              final oldTagId = t['id'] as int;
              final newTagId = tagIdMap[oldTagId];
              if (newTagId != null) {
                await txn.insert('prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
              }
            }
          }
        }
      }

      // Import System Prompts
      if (data['system_prompts'] != null) {
        for (var p in data['system_prompts']) {
          final Map<String, dynamic> row = Map.from(p)..remove('id');
          final List<dynamic>? tags = row['tags'];
          row.remove('tags');

          if (!replace) {
            final existing = await txn.query('system_prompts', where: 'title = ? AND type = ?', whereArgs: [row['title'], row['type']]);
            if (existing.isNotEmpty) continue;
          }
          
          final newPromptId = await txn.insert('system_prompts', row);
          if (tags != null) {
            for (var t in tags) {
              final oldTagId = t['id'] as int;
              final newTagId = tagIdMap[oldTagId];
              if (newTagId != null) {
                await txn.insert('system_prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
              }
            }
          }
        }
      }
    });
  }

  Future<void> _importTokenUsage(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> modelIdMap) async {
    if (rows == null || rows.isEmpty) return;
    final batch = txn.batch();
    for (var row in rows) {
      final Map<String, dynamic> map = Map.from(row)..remove('id');
      if (map['model_pk'] != null) {
        map['model_pk'] = modelIdMap[map['model_pk']];
      }
      batch.insert('token_usage', map);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<int, int>> _importModels(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> channelIdMap, Map<int, int> pricingGroupIdMap) async {
    final Map<int, int> idMap = {};
    if (rows == null) return idMap;
    for (var m in rows) {
      final oldId = m['id'] as int;
      final Map<String, dynamic> row = Map.from(m)..remove('id');
      if (row['channel_id'] != null) row['channel_id'] = channelIdMap[row['channel_id']];
      if (row['fee_group_id'] != null) row['fee_group_id'] = pricingGroupIdMap[row['fee_group_id']];
      final newId = await txn.insert('llm_models', row);
      idMap[oldId] = newId;
    }
    return idMap;
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

  Future<void> _importSystemPrompts(DatabaseExecutor txn, List<dynamic>? rows, Map<int, int> tagIdMap) async {
    if (rows == null) return;
    for (var p in rows) {
      final Map<String, dynamic> row = Map.from(p)..remove('id');
      final List<dynamic>? tagsFromData = row['tags'];
      row.remove('tags');
      
      final newPromptId = await txn.insert('system_prompts', row);

      if (tagsFromData != null) {
        for (var t in tagsFromData) {
          final oldTagId = t['id'] as int;
          final newTagId = tagIdMap[oldTagId];
          if (newTagId != null) {
            await txn.insert('system_prompt_tag_refs', {'prompt_id': newPromptId, 'tag_id': newTagId});
          }
        }
      }
    }
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

  Future<Map<int, int>> _importPricingGroups(DatabaseExecutor txn, List<dynamic>? rows) async {
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
}
