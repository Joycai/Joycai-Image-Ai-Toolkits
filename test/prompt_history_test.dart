import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/prompt_history_entry.dart';
import 'package:joycai_image_ai_toolkits/services/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/repositories/prompt_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the workbench prompt history against a real (in-memory) schema.
///
/// The list is capped and de-duplicated on every write, so these exercise what
/// survives a trim, and that the image and video panels never see each other's
/// prompts.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  Future<Database> openTestDb() async {
    final db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseService.dbVersion,
        onCreate: (db, version) => DatabaseMigration.onCreate(db),
      ),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    return db;
  }

  Future<void> record(Database db, PromptHistoryType type, String content) =>
      db.transaction((txn) => PromptRepository.addPromptHistoryInto(txn, type, content));

  Future<List<String>> contentsOf(Database db, PromptHistoryType type) async {
    final entries = await PromptRepository.getPromptHistoryFrom(db, type);
    return entries.map((e) => e.content).toList();
  }

  late Database db;
  setUp(() async => db = await openTestDb());
  tearDown(() async => db.close());

  test('returns prompts newest first', () async {
    await record(db, PromptHistoryType.image, 'first');
    await record(db, PromptHistoryType.image, 'second');
    await record(db, PromptHistoryType.image, 'third');

    expect(await contentsOf(db, PromptHistoryType.image), ['third', 'second', 'first']);
  });

  test('re-using a prompt bumps it instead of duplicating', () async {
    await record(db, PromptHistoryType.image, 'a');
    await record(db, PromptHistoryType.image, 'b');
    await record(db, PromptHistoryType.image, 'a');

    // Iterating on one prompt is the common case; duplicates would flush the list.
    expect(await contentsOf(db, PromptHistoryType.image), ['a', 'b']);
  });

  test('keeps only the newest 10, dropping the oldest', () async {
    for (var i = 1; i <= 13; i++) {
      await record(db, PromptHistoryType.image, 'prompt $i');
    }

    final contents = await contentsOf(db, PromptHistoryType.image);
    expect(contents.length, PromptRepository.promptHistoryLimit);
    expect(contents.first, 'prompt 13');
    expect(contents.last, 'prompt 4');
    expect(contents, isNot(contains('prompt 3')));
  });

  test('image and video histories are independent', () async {
    await record(db, PromptHistoryType.image, 'an image prompt');
    await record(db, PromptHistoryType.video, 'a video prompt');

    expect(await contentsOf(db, PromptHistoryType.image), ['an image prompt']);
    expect(await contentsOf(db, PromptHistoryType.video), ['a video prompt']);
  });

  test('a full video history does not evict image prompts', () async {
    await record(db, PromptHistoryType.image, 'keep me');
    for (var i = 1; i <= 12; i++) {
      await record(db, PromptHistoryType.video, 'video $i');
    }

    // The trim is per-type; a shared cap would have dropped this.
    expect(await contentsOf(db, PromptHistoryType.image), ['keep me']);
    expect((await contentsOf(db, PromptHistoryType.video)).length,
        PromptRepository.promptHistoryLimit);
  });

  test('blank prompts are not recorded', () async {
    await record(db, PromptHistoryType.image, '');
    await record(db, PromptHistoryType.image, '   \n  ');

    expect(await contentsOf(db, PromptHistoryType.image), isEmpty);
  });

  test('surrounding whitespace does not create a duplicate', () async {
    await record(db, PromptHistoryType.image, 'a cat');
    await record(db, PromptHistoryType.image, '  a cat\n');

    expect(await contentsOf(db, PromptHistoryType.image), ['a cat']);
  });

  test('clearing one type leaves the other intact', () async {
    await record(db, PromptHistoryType.image, 'an image prompt');
    await record(db, PromptHistoryType.video, 'a video prompt');

    await db.delete('prompt_history',
        where: 'type = ?', whereArgs: [PromptHistoryType.image.name]);

    expect(await contentsOf(db, PromptHistoryType.image), isEmpty);
    expect(await contentsOf(db, PromptHistoryType.video), ['a video prompt']);
  });

  test('upgrading from v27 creates the history table', () async {
    // The table is new in v28; an existing install must get it on upgrade, not
    // only through onCreate.
    final upgraded = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 27,
        onCreate: (db, version) => DatabaseMigration.onCreate(db),
      ),
    );
    await upgraded.execute('DROP TABLE IF EXISTS prompt_history');
    await DatabaseMigration.migrate(upgraded, 27, DatabaseService.dbVersion);

    await upgraded.transaction((txn) =>
        PromptRepository.addPromptHistoryInto(txn, PromptHistoryType.image, 'after upgrade'));
    final entries =
        await PromptRepository.getPromptHistoryFrom(upgraded, PromptHistoryType.image);

    expect(entries.map((e) => e.content), ['after upgrade']);
    await upgraded.close();
  });
}
