import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
          version: 7, // Incremented for billing mode and request fee
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      return await openDatabase(
        dbPath,
        version: 7,
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
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE source_directories (path TEXT PRIMARY KEY, is_selected INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, image_path TEXT, status TEXT, parameters TEXT, result_path TEXT, start_time TEXT, end_time TEXT, model_id TEXT)');
    await _createV2Tables(db);
    await _createV3Tables(db);
    await _createV4Tables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createV2Tables(db);
    if (oldVersion < 3) await _createV3Tables(db);
    if (oldVersion < 4) await _createV4Tables(db);
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE llm_models ADD COLUMN input_fee REAL DEFAULT 0.0');
      await db.execute('ALTER TABLE llm_models ADD COLUMN output_fee REAL DEFAULT 0.0');
    }
    if (oldVersion < 6) {
      // Check if model_id column exists in tasks table
      var tableInfo = await db.rawQuery('PRAGMA table_info(tasks)');
      bool hasModelId = tableInfo.any((column) => column['name'] == 'model_id');
      if (!hasModelId) {
        await db.execute('ALTER TABLE tasks ADD COLUMN model_id TEXT');
      }
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE llm_models ADD COLUMN billing_mode TEXT DEFAULT \'token\'');
      await db.execute('ALTER TABLE llm_models ADD COLUMN request_fee REAL DEFAULT 0.0');
      await db.execute('ALTER TABLE token_usage ADD COLUMN request_count INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE token_usage ADD COLUMN request_price REAL DEFAULT 0.0');
      await db.execute('ALTER TABLE token_usage ADD COLUMN billing_mode TEXT DEFAULT \'token\'');
    }
  }

  Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE llm_models (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model_id TEXT NOT NULL,
        model_name TEXT NOT NULL,
        type TEXT NOT NULL,
        tag TEXT NOT NULL,
        is_paid INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        input_fee REAL DEFAULT 0.0,
        output_fee REAL DEFAULT 0.0,
        billing_mode TEXT DEFAULT 'token',
        request_fee REAL DEFAULT 0.0
      )
    ''');
  }

  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE prompts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tag TEXT NOT NULL DEFAULT 'General',
        sort_order INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _createV4Tables(Database db) async {
    await db.execute('''
      CREATE TABLE token_usage (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id TEXT,
        model_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        input_tokens INTEGER DEFAULT 0,
        output_tokens INTEGER DEFAULT 0,
        input_price REAL DEFAULT 0.0,
        output_price REAL DEFAULT 0.0,
        request_count INTEGER DEFAULT 1,
        request_price REAL DEFAULT 0.0,
        billing_mode TEXT DEFAULT 'token'
      )
    ''');
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
}
