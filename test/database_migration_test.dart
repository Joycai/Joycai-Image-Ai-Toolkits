import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_stats.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/services/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the v30 upgrade (cache pricing) against a database shaped the way an
/// existing user's actually is — the columns are added by ALTER, not created
/// fresh, and the rows already in there have to keep pricing correctly.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  /// The `llm_models` table as it stood before v32, i.e. still carrying the
  /// redundant `type` column. Every fixture that calls `migrate` from below 32
  /// needs it, because the v32 step rebuilds this table.
  Future<void> createPreV32LlmModelsTable(Database db) async {
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
        request_fee REAL DEFAULT 0.0,
        channel_id INTEGER,
        fee_group_id INTEGER,
        force_view_all_images INTEGER DEFAULT 0,
        context_window INTEGER,
        supports_stream INTEGER DEFAULT 1,
        supports_standard INTEGER DEFAULT 1,
        est_mean_ms REAL DEFAULT 0.0,
        est_sd_ms REAL DEFAULT 0.0,
        tasks_since_update INTEGER DEFAULT 0
      )
    ''');
  }

  /// The `tasks` table as it stood before v31, i.e. without its logs column.
  ///
  /// Every fixture here needs it: `migrate` keys each step off `oldVersion`
  /// alone and ignores `newVersion`, so any migrate() call from below 31 runs
  /// the v31 step and touches this table.
  Future<void> createPreV31TasksTable(Database db) async {
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY, image_path TEXT, status TEXT, parameters TEXT,
        result_path TEXT, start_time TEXT, end_time TEXT, model_id TEXT,
        type TEXT DEFAULT 'imageProcess', use_stream INTEGER DEFAULT 1,
        model_pk INTEGER, channel_tag TEXT, channel_color INTEGER
      )
    ''');
  }

  /// A v29-shaped database: the pre-cache-pricing schema, built by hand because
  /// `onCreate` would otherwise hand us the current one and make the migration
  /// a no-op.
  Future<Database> openV29Db() async {
    final db = await factory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 29));
    await createPreV31TasksTable(db);
    await createPreV32LlmModelsTable(db);
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
    await db.execute('''
      CREATE TABLE usage_checkpoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        total_input_tokens INTEGER DEFAULT 0,
        total_output_tokens INTEGER DEFAULT 0,
        total_request_count INTEGER DEFAULT 0,
        total_cost REAL DEFAULT 0.0,
        metadata TEXT
      )
    ''');
    return db;
  }

  Future<Set<String>> columnsOf(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((c) => c['name'] as String).toSet();
  }

  test('v30 adds the cache columns to an existing database', () async {
    final db = await openV29Db();
    addTearDown(db.close);

    await DatabaseMigration.migrate(db, 29, 30);

    expect(await columnsOf(db, 'fee_groups'), contains('cache_input_price'));
    expect(await columnsOf(db, 'token_usage'), containsAll(['cache_tokens', 'cache_price']));
    expect(await columnsOf(db, 'usage_checkpoints'), contains('total_cache_tokens'));
  });

  test('pre-existing fee groups migrate to an unset (not free) cache rate', () async {
    final db = await openV29Db();
    addTearDown(db.close);
    await db.insert('fee_groups', {'name': 'Old Group', 'input_price': 3.0, 'output_price': 9.0});

    await DatabaseMigration.migrate(db, 29, 30);

    final group = PricingGroup.fromMap((await db.query('fee_groups')).single);
    // Null, not 0.0 — an untouched group must keep billing cache hits at the
    // input rate rather than silently making them free.
    expect(group.cacheInputPrice, isNull);
    expect(group.effectiveCacheInputPrice, 3.0);
  });

  test('usage rows recorded before the upgrade still price unchanged', () async {
    final db = await openV29Db();
    addTearDown(db.close);
    await db.insert('token_usage', {
      'model_id': 'gemini-2.5-pro',
      'timestamp': DateTime(2026, 1, 1).toIso8601String(),
      'input_tokens': 1000000,
      'output_tokens': 1000000,
      'input_price': 2.0,
      'output_price': 10.0,
      'billing_mode': 'token',
    });

    await DatabaseMigration.migrate(db, 29, 30);

    final row = (await db.query('token_usage')).single;
    expect(row['cache_tokens'], 0);
    expect(row['cache_price'], isNull);
    expect(calculateRowCost(row), closeTo(12.0, 1e-9));
  });

  test('a fresh database is created with the cache columns', () async {
    final db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 30, onCreate: (db, _) => DatabaseMigration.onCreate(db)),
    );
    addTearDown(db.close);

    expect(await columnsOf(db, 'fee_groups'), contains('cache_input_price'));
    expect(await columnsOf(db, 'token_usage'), containsAll(['cache_tokens', 'cache_price']));
    expect(await columnsOf(db, 'usage_checkpoints'), contains('total_cache_tokens'));
  });

  /// A v30 database carrying only what the v31 upgrade touches.
  Future<Database> openV30TasksDb() async {
    final db = await factory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 30));
    await createPreV31TasksTable(db);
    await createPreV32LlmModelsTable(db);
    return db;
  }

  test('v38 adds the operation provenance columns to tasks', () async {
    final db = await openV30TasksDb();
    addTearDown(db.close);

    await DatabaseMigration.migrate(db, 37, 38);

    expect(await columnsOf(db, 'tasks'),
        containsAll(['operation_name', 'operation_surface']));

    // Pre-v38 rows read back with null provenance — the poll router treats
    // that as "fall back to the id-prefix guards", never as an error.
    await db.insert('tasks', {
      'id': 'pre-v38-task',
      'image_path': '[]',
      'status': 'processing',
      'parameters': '{}',
      'result_path': '[]',
      'model_id': 'sora-2',
    });
    final row = (await db.query('tasks')).single;
    expect(TaskItem.fromMap(row).operationSurface, isNull);

    // Re-running the step (upgrade/downgrade round trip) must be a no-op.
    await DatabaseMigration.migrate(db, 37, 38);
  });

  test('v31 adds the logs column to an existing database', () async {
    final db = await openV30TasksDb();
    addTearDown(db.close);

    await DatabaseMigration.migrate(db, 30, 31);

    expect(await columnsOf(db, 'tasks'), contains('logs'));
  });

  test('tasks recorded before the upgrade survive it with an empty log', () async {
    final db = await openV30TasksDb();
    addTearDown(db.close);
    await db.insert('tasks', {
      'id': 'old-task',
      'image_path': '["a.png"]',
      'status': 'failed',
      'parameters': '{}',
      'result_path': '[]',
      'model_id': 'gpt-image-2',
    });

    await DatabaseMigration.migrate(db, 30, 31);

    final row = (await db.query('tasks')).single;
    expect(row['logs'], isNull);
    // The row is still readable — a null log must not sink the queue reload.
    expect(TaskItem.fromMap(row).logs, isEmpty);
  });

  test('v32 drops llm_models.type and keeps every row intact', () async {
    final db = await factory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 31));
    addTearDown(db.close);
    await createPreV32LlmModelsTable(db);
    await db.insert('llm_models', {
      'model_id': 'gemini-3-pro-image',
      'model_name': 'Nano Banana Pro',
      'type': 'google-genai', // the stale copy being dropped
      'tag': 'image',
      'is_paid': 1,
      'sort_order': 3,
      'channel_id': 7,
      'fee_group_id': 2,
      'force_view_all_images': 1,
      'context_window': 1048576,
      'supports_stream': 0,
      'supports_standard': 1,
      'est_mean_ms': 1234.5,
      'tasks_since_update': 4,
    });

    await DatabaseMigration.migrate(db, 31, 32);

    final columns = await columnsOf(db, 'llm_models');
    expect(columns, isNot(contains('type')));
    expect(columns, containsAll(['model_id', 'tag', 'channel_id', 'fee_group_id', 'context_window', 'supports_stream']));

    final row = (await db.query('llm_models')).single;
    expect(row['model_id'], 'gemini-3-pro-image');
    expect(row['model_name'], 'Nano Banana Pro');
    expect(row['tag'], 'image');
    expect(row['is_paid'], 1);
    expect(row['sort_order'], 3);
    expect(row['channel_id'], 7);
    expect(row['fee_group_id'], 2);
    expect(row['force_view_all_images'], 1);
    expect(row['context_window'], 1048576);
    expect(row['supports_stream'], 0);
    expect(row['supports_standard'], 1);
    expect(row['est_mean_ms'], 1234.5);
    expect(row['tasks_since_update'], 4);
  });

  test('a task written after the upgrade reloads with its log', () async {
    final db = await openV30TasksDb();
    addTearDown(db.close);
    await DatabaseMigration.migrate(db, 30, 31);

    final task = TaskItem(id: 't1', imagePaths: [], modelId: 'm', parameters: {})
      ..addLog('Start processing')
      ..addLog('Error: quota exceeded');
    await db.insert('tasks', task.toMap());

    final reloaded = TaskItem.fromMap((await db.query('tasks')).single);
    expect(reloaded.logs, hasLength(2));
    expect(reloaded.logs.last, contains('quota exceeded'));
  });

  test('a fresh database is created with the logs column', () async {
    final db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 31, onCreate: (db, _) => DatabaseMigration.onCreate(db)),
    );
    addTearDown(db.close);

    expect(await columnsOf(db, 'tasks'), contains('logs'));
  });
}
