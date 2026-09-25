import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/context_budget.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// [ContextBudget.resolveWindow] is the one place the stored window is looked
/// up by model, and it used to read `DatabaseService()` — the app's real file —
/// whatever database its caller was working against. Everything else in
/// `context_budget_test.dart` is pure arithmetic; this file is the database
/// half.
void main() {
  sqfliteFfiInit();

  late DatabaseService db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() async => closeTestDatabase(db));

  Future<int> addModel(String modelId, {int? contextWindow}) async {
    final channelId = await db.addChannel(
      LLMChannel(
        displayName: 'Test Channel',
        type: 'openai-api',
        endpoint: 'https://test.example.com/v1',
        apiKey: 'key-123',
      ),
    );
    return db.addModel(
      LLMModel(
        modelId: modelId,
        modelName: modelId,
        tag: 'chat',
        channelId: channelId,
        contextWindow: contextWindow,
      ),
    );
  }

  test('finds the window by database id', () async {
    final id = await addModel('local-llama', contextWindow: 8192);
    expect(await ContextBudget.resolveWindow(id, database: db), 8192);
  });

  test('finds the window by legacy string model id', () async {
    await addModel('local-llama', contextWindow: 4096);
    expect(await ContextBudget.resolveWindow('local-llama', database: db), 4096);
  });

  test('keeps the tri-state: unset stays null, unlimited stays 0', () async {
    final unset = await addModel('unset-model');
    final unlimited = await addModel('unlimited-model', contextWindow: 0);

    expect(await ContextBudget.resolveWindow(unset, database: db), isNull);
    expect(await ContextBudget.resolveWindow(unlimited, database: db), 0);
  });

  test('is null for a model the database does not have', () async {
    await addModel('local-llama', contextWindow: 8192);
    expect(await ContextBudget.resolveWindow('nobody', database: db), isNull);
    expect(await ContextBudget.resolveWindow(99999, database: db), isNull);
  });

  test('reads the database it was given, not another one', () async {
    final other = await openTestDatabase();
    addTearDown(() => closeTestDatabase(other));

    final id = await addModel('local-llama', contextWindow: 8192);

    // `other` has no models at all, so a lookup against it must not find the
    // row that lives in `db`.
    expect(await ContextBudget.resolveWindow(id, database: other), isNull);
    expect(await ContextBudget.resolveWindow('local-llama', database: other), isNull);
    expect(await ContextBudget.resolveWindow(id, database: db), 8192);
  });
}
