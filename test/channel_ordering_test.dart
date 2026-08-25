import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/services/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screenshots/harness/fixture_env.dart';

/// The channel rail became sortable in v37. Two things have to hold: an
/// upgrade must not visibly reshuffle a list the user has been reading by
/// position, and the stored arrangement must survive everything that touches
/// a channel afterwards.
void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();

  group('v37 migration', () {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;

    /// `llm_channels` as it stood before v37 — no `sort_order`.
    Future<Database> preV37Database(List<String> names) async {
      final db = await factory.openDatabase(inMemoryDatabasePath);
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
      for (final name in names) {
        await db.insert('llm_channels', {
          'display_name': name,
          'endpoint': 'https://example.com/v1',
          'api_key': 'k',
          'type': 'openai-api-rest',
        });
      }
      return db;
    }

    Future<List<String>> orderedNames(Database db) async {
      final rows =
          await db.query('llm_channels', orderBy: 'sort_order ASC, id ASC');
      return [for (final r in rows) r['display_name'] as String];
    }

    test('backfills so the rail looks exactly as it did before the upgrade',
        () async {
      final db = await preV37Database(['A', 'B', 'C']);
      // Only the v37 step: the fixture table is post-v36 in every other way.
      await DatabaseMigration.migrate(db, 36, 37);

      expect(await orderedNames(db), ['A', 'B', 'C']);
      final rows = await db.query('llm_channels', orderBy: 'id');
      for (final row in rows) {
        expect(row['sort_order'], row['id'],
            reason: 'seeded with the id, so rowid order is preserved');
      }
      await db.close();
    });

    test('a later migrate() run does not clobber a user-made arrangement',
        () async {
      final db = await preV37Database(['A', 'B', 'C']);
      await DatabaseMigration.migrate(db, 36, 37);

      // The user drags C to the top.
      await db.update('llm_channels', {'sort_order': 0},
          where: 'display_name = ?', whereArgs: ['C']);
      expect(await orderedNames(db), ['C', 'A', 'B']);

      // A build that re-runs the step (a downgrade/upgrade round-trip, a
      // repaired version row) must find the column present and leave the
      // data alone — this is what `_addColumnIfNotExists` returning false buys.
      await DatabaseMigration.migrate(db, 36, 37);
      expect(await orderedNames(db), ['C', 'A', 'B']);
      await db.close();
    });
  });

  group('repository ordering', () {
    late FixtureEnv env;
    late DatabaseService db;

    setUpAll(() async {
      env = installFixtureEnv(binding);
      db = DatabaseService();
    });

    tearDownAll(() => env.dispose());

    Future<int> addChannel(String name) => db.addChannel(LLMChannel(
          displayName: name,
          endpoint: 'https://example.com/v1',
          apiKey: 'k',
          type: 'openai-api-rest',
        ).toMap(includeId: false));

    Future<List<String>> names() async =>
        [for (final c in await db.getChannels()) c.displayName];

    test('new channels append, reorder persists, and later adds still append',
        () async {
      final a = await addChannel('A');
      final b = await addChannel('B');
      final c = await addChannel('C');
      expect(await names(), ['A', 'B', 'C'],
          reason: 'a new channel belongs at the end of the rail');

      await db.updateChannelOrder([c, a, b]);
      expect(await names(), ['C', 'A', 'B']);

      // The append must key off MAX(sort_order), not the row count: after the
      // reorder above the orders are 0,1,2 and a count-based guess would
      // collide with the last row instead of following it.
      await addChannel('D');
      expect(await names(), ['C', 'A', 'B', 'D']);
    });

    test('editing a channel leaves its position alone', () async {
      final channels = await db.getChannels();
      final target = channels.firstWhere((c) => c.displayName == 'A');
      final before = await names();

      // The editor builds a fresh LLMChannel with no knowledge of the rail —
      // the reason `sort_order` is kept out of `toMap`.
      await db.updateChannel(
        target.id!,
        LLMChannel(
          displayName: 'A (renamed)',
          endpoint: target.endpoint,
          apiKey: target.apiKey,
          type: target.type,
        ).toMap(includeId: false),
      );

      final after = await names();
      expect(after.indexOf('A (renamed)'), before.indexOf('A'));
    });
  });
}
