import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_stats.dart';
import 'package:joycai_image_ai_toolkits/services/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the v30 upgrade (cache pricing) against a database shaped the way an
/// existing user's actually is — the columns are added by ALTER, not created
/// fresh, and the rows already in there have to keep pricing correctly.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  /// A v29-shaped database: the pre-cache-pricing schema, built by hand because
  /// `onCreate` would otherwise hand us the current one and make the migration
  /// a no-op.
  Future<Database> openV29Db() async {
    final db = await factory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 29));
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
}
