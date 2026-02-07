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
          version: 18, // Incremented for Task Progress Estimation
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      return await openDatabase(
        dbPath,
        version: 18,
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
    return await db.rawQuery('''
      SELECT p.*, t.name as tag_name, t.color as tag_color, t.is_system as tag_is_system
      FROM prompts p
      LEFT JOIN prompt_tags t ON p.tag_id = t.id
      ORDER BY p.sort_order ASC
    ''');
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

  Future<List<double>> getTaskDurations(int modelPk, int limit) async {
    final db = await database;
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

  Future<void> updateModelEstimation(int modelPk, double mean, double sd, int tasksSinceUpdate) async {
    final db = await database;
    await db.update(
      'llm_models',
      {
        'est_mean_ms': mean,
        'est_sd_ms': sd,
        'tasks_since_update': tasksSinceUpdate,
      },
      where: 'id = ?',
      whereArgs: [modelPk],
    );
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

  // System Prompts Methods
  Future<int> addSystemPrompt(Map<String, dynamic> prompt) async {
    final db = await database;
    return await db.insert('system_prompts', prompt);
  }

  Future<void> updateSystemPrompt(int id, Map<String, dynamic> prompt) async {
    final db = await database;
    await db.update('system_prompts', prompt, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteSystemPrompt(int id) async {
    final db = await database;
    await db.delete('system_prompts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getSystemPrompts({String? type}) async {
    final db = await database;
    if (type != null) {
      return await db.query('system_prompts', where: 'type = ?', whereArgs: [type]);
    }
    return await db.query('system_prompts');
  }

  // Backup & Restore
  Future<Map<String, dynamic>> getAllDataRaw() async {
    final db = await database;
    return {
      'settings': await db.query('settings'),
      'llm_channels': await db.query('llm_channels'),
      'llm_models': await db.query('llm_models'),
      'prompt_tags': await db.query('prompt_tags'),
      'prompts': await db.query('prompts'),
      'system_prompts': await db.query('system_prompts'),
      'fee_groups': await db.query('fee_groups'),
      'source_directories': await db.query('source_directories'),
    };
  }

  Future<void> clearAllData(DatabaseExecutor txn) async {
    await txn.delete('settings');
    await txn.delete('llm_channels');
    await txn.delete('llm_models');
    await txn.delete('prompt_tags');
    await txn.delete('prompts');
    await txn.delete('system_prompts');
    await txn.delete('fee_groups');
    await txn.delete('source_directories');
  }

  Future<void> restoreBackup(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      await clearAllData(txn);

      final channelIdMap = await _importChannels(txn, data['llm_channels']);
      final feeGroupIdMap = await _importFeeGroups(txn, data['fee_groups']);
      await _importModels(txn, data['llm_models'], channelIdMap, feeGroupIdMap);
      
      final tagIdMap = await _importPromptTags(txn, data['prompt_tags']);
      await _importPrompts(txn, data['prompts'], tagIdMap);
      
      await _importSimpleTable(txn, 'settings', data['settings']);
      await _importSimpleTable(txn, 'system_prompts', data['system_prompts']);
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
    final batch = txn.batch();
    for (var p in rows) {
      final Map<String, dynamic> row = Map.from(p)..remove('id');
      if (row['tag_id'] != null) row['tag_id'] = tagIdMap[row['tag_id']];
      batch.insert('prompts', row);
    }
    await batch.commit(noResult: true);
  }
}
