import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_controller.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// The usage views' controller, on an injected database. The one-model clear
/// used to be the list's own `DatabaseService()` call followed by the
/// controller's reload — two objects that happened to share the singleton.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseService db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => closeTestDatabase(db));

  /// One request of [modelId], inside the default week range.
  Future<void> record(String modelId, {int minutesAgo = 5}) => db.recordTokenUsage(
    TokenUsage(
      taskId: '$modelId-$minutesAgo',
      modelId: modelId,
      timestamp: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      inputTokens: 10,
      outputTokens: 5,
    ),
  );

  test('clearModelUsage deletes one model\'s rows and reloads on the same database', () async {
    await record('a', minutesAgo: 1);
    await record('a', minutesAgo: 2);
    await record('b', minutesAgo: 3);
    final c = UsageController(models: () => const [], database: db);
    addTearDown(c.dispose);
    await c.load(reset: true);
    expect(c.rows.map((r) => r.modelId), ['a', 'a', 'b']);

    await c.clearModelUsage('a');

    expect(c.rows.map((r) => r.modelId), ['b']);
    expect(c.totalRecords, 1);
    expect(c.stats.totalRequestCount, 1);
    expect((await db.getTokenUsage()).map((r) => r.modelId), ['b']);
  });
}
