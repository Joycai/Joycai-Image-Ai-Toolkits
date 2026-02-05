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
          version: 10, // Incremented for Dynamic Channels
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      return await openDatabase(
        dbPath,
        version: 10,
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
    await _createV8Tables(db);
    await _createV9Tables(db);
    await _createV10Tables(db);
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
    if (oldVersion < 8) await _createV8Tables(db);
    if (oldVersion < 9) await _createV9Tables(db);
    if (oldVersion < 10) await _createV10Tables(db);
  }

  Future<void> _createV10Tables(Database db) async {
    // 1. Create llm_channels table
    await db.execute('''
      CREATE TABLE llm_channels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        display_name TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        api_key TEXT NOT NULL,
        type TEXT NOT NULL,
        enable_discovery INTEGER DEFAULT 1,
        tag TEXT,
        tag_color INTEGER
      )
    ''');

    // 2. Add channel_id to llm_models
    await db.execute('ALTER TABLE llm_models ADD COLUMN channel_id INTEGER REFERENCES llm_channels(id)');

    // 3. Migrate existing settings to channels
    final settings = await db.query('settings');
    final Map<String, String> settingsMap = {
      for (var s in settings) s['key'] as String: s['value'] as String
    };

    Future<int?> createChannel(String prefix, String defaultName, String type) async {
      final apiKey = settingsMap['${prefix}_apikey'];
      final endpoint = settingsMap['${prefix}_endpoint'];
      if (apiKey == null || apiKey.isEmpty) return null;

      return await db.insert('llm_channels', {
        'display_name': defaultName,
        'endpoint': endpoint ?? (type.contains('google') ? 'https://generativelanguage.googleapis.com' : 'https://api.openai.com/v1'),
        'api_key': apiKey,
        'type': type,
        'enable_discovery': 1,
        'tag': defaultName.split(' ').first,
        'tag_color': 0xFF607D8B, // BlueGrey
      });
    }

    final googleFreeId = await createChannel('google_free', 'Google GenAI (Free)', 'google-genai-rest');
    final googlePaidId = await createChannel('google_paid', 'Google GenAI (Paid)', 'google-genai-rest');
    final openaiId = await createChannel('openai', 'OpenAI API', 'openai-api-rest');

    // 4. Update existing models to link to channels
    final models = await db.query('llm_models');
    for (var model in models) {
      int? channelId;
      final type = model['type'] as String;
      final isPaid = model['is_paid'] == 1;

      if (type == 'google-genai') {
        channelId = isPaid ? googlePaidId : googleFreeId;
      } else if (type == 'openai-api') {
        channelId = openaiId;
      }

      if (channelId != null) {
        await db.update('llm_models', {'channel_id': channelId}, where: 'id = ?', whereArgs: [model['id']]);
      }
    }
  }

  Future<void> _createV9Tables(Database db) async {
    // 1. Add model_pk to token_usage
    await db.execute('ALTER TABLE token_usage ADD COLUMN model_pk INTEGER');

    // 2. Migrate existing usage to link to models
    final allUsageEntries = await db.query('token_usage');
    final allModels = await db.query('llm_models');
    
    for (var usageEntry in allUsageEntries) {
      final modelId = usageEntry['model_id'] as String;
      // Find first matching model
      final matchingModel = allModels.cast<Map<String, dynamic>?>().firstWhere(
        (model) => model?['model_id'] == modelId,
        orElse: () => null,
      );
      if (matchingModel != null) {
        await db.update('token_usage', {'model_pk': matchingModel['id']}, where: 'id = ?', whereArgs: [usageEntry['id']]);
      }
    }
  }

  Future<void> _createV8Tables(Database db) async {
    // 1. Create fee_groups table
    await db.execute('''
      CREATE TABLE fee_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        billing_mode TEXT DEFAULT 'token',
        input_price REAL DEFAULT 0.0,
        output_price REAL DEFAULT 0.0,
        request_price REAL DEFAULT 0.0
      )
    ''');

    // 2. Add fee_group_id to llm_models
    await db.execute('ALTER TABLE llm_models ADD COLUMN fee_group_id INTEGER REFERENCES fee_groups(id)');

    // 3. Migrate existing fees to new groups
    final allLlmModels = await db.query('llm_models');
    for (var llmModel in allLlmModels) {
      final name = '${llmModel['model_name']} Fee';
      final mode = llmModel['billing_mode'] as String? ?? 'token';
      final feeGroupId = await db.insert('fee_groups', {
        'name': name,
        'billing_mode': mode,
        'input_price': llmModel['input_fee'] ?? 0.0,
        'output_price': llmModel['output_fee'] ?? 0.0,
        'request_price': llmModel['request_fee'] ?? 0.0,
      });
      await db.update('llm_models', {'fee_group_id': feeGroupId}, where: 'id = ?', whereArgs: [llmModel['id']]);
    }

    // 4. Add model_pk to tasks
    await db.execute('ALTER TABLE tasks ADD COLUMN model_pk INTEGER');
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
}
