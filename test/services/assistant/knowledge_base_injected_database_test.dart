import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// Most of [KnowledgeBaseService] is plain file access, but two things are
/// `settings` rows: the knowledge-base root and the three write switches. Both
/// are read from and written to the database the service was constructed over,
/// and nothing else — so a caller holding its own database (the task queue, a
/// test) decides where the root points and whether the agent may touch the
/// user's rule files at all. `KnowledgeBaseService()` with no argument is still
/// the app-wide instance, which is what the ~30 file-only call sites use.
void main() {
  sqfliteFfiInit();

  late DatabaseService db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() async => closeTestDatabase(db));

  test('the root round-trips through the injected database', () async {
    final kb = KnowledgeBaseService(database: db);
    expect(await kb.getRoot(), isNull);

    await kb.setRoot(r'D:\rules');

    expect(await kb.getRoot(), r'D:\rules');
    expect(await db.getSetting(KnowledgeBaseService.settingKey), r'D:\rules');
  });

  test('a blank root row reads as "not set"', () async {
    await db.saveSetting(KnowledgeBaseService.settingKey, '   ');
    expect(await KnowledgeBaseService(database: db).getRoot(), isNull);
  });

  test('the write policy round-trips through the injected database', () async {
    final kb = KnowledgeBaseService(database: db);
    expect(await kb.getWritePolicy(), KbWritePolicy.defaults);

    // Every field flipped away from its default, so a policy that silently
    // fell back to the defaults cannot pass.
    await kb.setWritePolicy(
      const KbWritePolicy(allowWrites: false, confirmEachWrite: false, backupBeforeOverwrite: true),
    );

    final policy = await kb.getWritePolicy();
    expect(policy.allowWrites, isFalse);
    expect(policy.confirmEachWrite, isFalse);
    expect(policy.backupBeforeOverwrite, isTrue);
  });

  test('two instances over two databases do not see each other', () async {
    final other = await openTestDatabase();
    addTearDown(() => closeTestDatabase(other));

    await KnowledgeBaseService(database: other).setRoot(r'D:\other');
    await KnowledgeBaseService(database: other).setWritePolicy(
      const KbWritePolicy(allowWrites: false, confirmEachWrite: false, backupBeforeOverwrite: true),
    );

    // Nothing leaked into the database this test owns...
    expect(await KnowledgeBaseService(database: db).getRoot(), isNull);
    expect(await KnowledgeBaseService(database: db).getWritePolicy(), KbWritePolicy.defaults);
    // ...and the one that was written still holds it.
    expect(await KnowledgeBaseService(database: other).getRoot(), r'D:\other');
    expect((await KnowledgeBaseService(database: other).getWritePolicy()).allowWrites, isFalse);
  });

  test('no database means the app-wide instance, unchanged', () {
    expect(identical(KnowledgeBaseService(), KnowledgeBaseService()), isTrue);
    expect(identical(KnowledgeBaseService(), KnowledgeBaseService(database: db)), isFalse);
  });
}
