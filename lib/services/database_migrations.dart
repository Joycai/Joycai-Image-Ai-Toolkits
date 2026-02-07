import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseMigration {
  static Future<void> migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createV2Tables(db);
    if (oldVersion < 3) await _createV3Tables(db);
    if (oldVersion < 4) await _createV4Tables(db);
    if (oldVersion < 5) {
      await _addColumnIfNotExists(db, 'llm_models', 'input_fee', 'REAL DEFAULT 0.0');
      await _addColumnIfNotExists(db, 'llm_models', 'output_fee', 'REAL DEFAULT 0.0');
    }
    if (oldVersion < 6) {
      var tableInfo = await db.rawQuery('PRAGMA table_info(tasks)');
      bool hasModelId = tableInfo.any((column) => column['name'] == 'model_id');
      if (!hasModelId) {
        await db.execute('ALTER TABLE tasks ADD COLUMN model_id TEXT');
      }
    }
    if (oldVersion < 7) {
      await _addColumnIfNotExists(db, 'llm_models', 'billing_mode', "TEXT DEFAULT 'token'");
      await _addColumnIfNotExists(db, 'llm_models', 'request_fee', 'REAL DEFAULT 0.0');
      await _addColumnIfNotExists(db, 'token_usage', 'request_count', 'INTEGER DEFAULT 1');
      await _addColumnIfNotExists(db, 'token_usage', 'request_price', 'REAL DEFAULT 0.0');
      await _addColumnIfNotExists(db, 'token_usage', 'billing_mode', "TEXT DEFAULT 'token'");
    }
    if (oldVersion < 8) await _createV8Tables(db);
    if (oldVersion < 9) await _createV9Tables(db);
    if (oldVersion < 10) await _createV10Tables(db);
    if (oldVersion < 11) await _createV11Tables(db);
    if (oldVersion < 12) await _createV12Tables(db);
    if (oldVersion < 13) await _createV13Tables(db);
    if (oldVersion < 14) await _createV14Tables(db);
    if (oldVersion < 15) await _createV15Tables(db);
    if (oldVersion < 16) await _createV16Tables(db);
    if (oldVersion < 17) await _createV17Tables(db);
  }

  static Future<void> onCreate(Database db) async {
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('CREATE TABLE source_directories (path TEXT PRIMARY KEY, is_selected INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, image_path TEXT, status TEXT, parameters TEXT, result_path TEXT, start_time TEXT, end_time TEXT, model_id TEXT, type TEXT DEFAULT \'imageProcess\')');
    
    await _createV2Tables(db);
    await _createV3Tables(db);
    await _createV4Tables(db);
    await _createV8Tables(db);
    await _createV9Tables(db);
    await _createV10Tables(db);
    await _createV11Tables(db);
    await _createV12Tables(db);
    await _createV13Tables(db);
    await _createV14Tables(db);
    await _createV15Tables(db);
    await _createV16Tables(db);
    await _createV17Tables(db);
  }

  static Future<void> _createV17Tables(Database db) async {
    await db.execute('''
      CREATE TABLE downloader_cookies (
        host TEXT PRIMARY KEY,
        cookies TEXT NOT NULL,
        last_used TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createV16Tables(Database db) async {
    await _addColumnIfNotExists(db, 'tasks', 'type', "TEXT DEFAULT 'imageProcess'");
  }

  static Future<void> _createV15Tables(Database db) async {
    await _addColumnIfNotExists(db, 'prompts', 'is_markdown', 'INTEGER DEFAULT 0');
    await _addColumnIfNotExists(db, 'system_prompts', 'is_markdown', 'INTEGER DEFAULT 0');
  }

  static Future<void> _createV2Tables(Database db) async {
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

  static Future<void> _createV3Tables(Database db) async {
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

  static Future<void> _createV4Tables(Database db) async {
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

  static Future<void> _createV8Tables(Database db) async {
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
    await db.execute('ALTER TABLE llm_models ADD COLUMN fee_group_id INTEGER REFERENCES fee_groups(id)');
    
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
    await db.execute('ALTER TABLE tasks ADD COLUMN model_pk INTEGER');
  }

  static Future<void> _createV9Tables(Database db) async {
    await db.execute('ALTER TABLE token_usage ADD COLUMN model_pk INTEGER');
    final allUsageEntries = await db.query('token_usage');
    final allModels = await db.query('llm_models');
    for (var usageEntry in allUsageEntries) {
      final modelId = usageEntry['model_id'] as String;
      final matchingModel = allModels.cast<Map<String, dynamic>?>().firstWhere(
        (model) => model?['model_id'] == modelId,
        orElse: () => null,
      );
      if (matchingModel != null) {
        await db.update('token_usage', {'model_pk': matchingModel['id']}, where: 'id = ?', whereArgs: [usageEntry['id']]);
      }
    }
  }

  static Future<void> _createV10Tables(Database db) async {
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
    await db.execute('ALTER TABLE llm_models ADD COLUMN channel_id INTEGER REFERENCES llm_channels(id)');
    
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
        'tag_color': 0xFF607D8B,
      });
    }

    final googleFreeId = await createChannel('google_free', 'Google GenAI (Free)', 'google-genai-rest');
    final googlePaidId = await createChannel('google_paid', 'Google GenAI (Paid)', 'google-genai-rest');
    final openaiId = await createChannel('openai', 'OpenAI API', 'openai-api-rest');

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

  static Future<void> _createV14Tables(Database db) async {
    // 1. Create system_prompts table
    await db.execute('''
      CREATE TABLE system_prompts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT NOT NULL
      )
    ''');

    // 2. Migrate existing "Refiner" prompts
    // Find the Refiner tag
    final refinerTag = await db.query('prompt_tags', where: 'name = ?', whereArgs: ['Refiner'], limit: 1);
    if (refinerTag.isNotEmpty) {
      final refinerTagId = refinerTag.first['id'] as int;
      
      // Get all prompts with this tag
      final refinerPrompts = await db.query('prompts', where: 'tag_id = ?', whereArgs: [refinerTagId]);
      
      for (var p in refinerPrompts) {
        await db.insert('system_prompts', {
          'title': p['title'],
          'content': p['content'],
          'type': 'refiner',
        });
      }

      // Delete from prompts table
      await db.delete('prompts', where: 'tag_id = ?', whereArgs: [refinerTagId]);
      
      // Delete the system tag
      await db.delete('prompt_tags', where: 'id = ?', whereArgs: [refinerTagId]);
    }
  }

  static Future<void> _createV13Tables(Database db) async {
    // 1. Create prompt_tags table
    await db.execute('''
      CREATE TABLE prompt_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color INTEGER,
        is_system INTEGER DEFAULT 0
      )
    ''');

    // 2. Add tag_id to prompts
    await db.execute('ALTER TABLE prompts ADD COLUMN tag_id INTEGER REFERENCES prompt_tags(id)');

    // 3. Migrate existing tags
    final allPrompts = await db.query('prompts');
    final Set<String> uniqueTags = allPrompts.map((p) => p['tag'] as String).toSet();
    
    // Ensure "General" and "Refiner" exist even if no prompts use them
    uniqueTags.add('General');
    uniqueTags.add('Refiner');

    final Map<String, int> tagMap = {};
    for (var tagName in uniqueTags) {
      final isRefiner = tagName == 'Refiner';
      final id = await db.insert('prompt_tags', {
        'name': tagName,
        'color': isRefiner ? 0xFF9C27B0 : 0xFF607D8B, // Purple for Refiner, BlueGrey for others
        'is_system': isRefiner ? 1 : 0,
      });
      tagMap[tagName] = id;
    }

    // 4. Update prompts with tag_id
    for (var p in allPrompts) {
      final tagName = p['tag'] as String;
      final tagId = tagMap[tagName];
      if (tagId != null) {
        await db.update('prompts', {'tag_id': tagId}, where: 'id = ?', whereArgs: [p['id']]);
      }
    }
  }

  static Future<void> _createV12Tables(Database db) async {
    await _addColumnIfNotExists(db, 'prompts', 'tag_color', 'INTEGER');
  }

  static Future<void> _createV11Tables(Database db) async {
    await _addColumnIfNotExists(db, 'tasks', 'channel_tag', 'TEXT');
    await _addColumnIfNotExists(db, 'tasks', 'channel_color', 'INTEGER');
  }

  static Future<void> _addColumnIfNotExists(Database db, String tableName, String columnName, String columnType) async {
    var tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');
    bool columnExists = tableInfo.any((column) => column['name'] == columnName);
    if (!columnExists) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $columnType');
    }
  }
}
