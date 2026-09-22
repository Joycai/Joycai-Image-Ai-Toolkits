import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/models/usage_checkpoint.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/task_repository.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// The usage and task repositories against the real schema: what goes in as a
/// model comes out as the same model. `token_usage_test.dart` pins the map
/// round trip; this pins that the maps name columns the table actually has.
void main() {
  sqfliteFfiInit();

  late DatabaseService db;
  late UsageRepository usage;

  setUp(() async {
    db = await openTestDatabase();
    usage = UsageRepository(db: db);
  });
  tearDown(() => closeTestDatabase(db));

  final at = DateTime(2026, 9, 1, 12);

  test('a recorded row reads back as the same usage', () async {
    await usage.recordTokenUsage(TokenUsage(
      taskId: 'req_1',
      modelId: 'm',
      modelDbId: 7,
      timestamp: at,
      inputTokens: 10,
      cacheTokens: 4,
      outputTokens: 6,
      inputPrice: 2.0,
      cachePrice: 0.5,
      outputPrice: 8.0,
    ));

    final row = (await usage.getTokenUsage()).single;

    expect(row.id, isNotNull);
    expect(row.taskId, 'req_1');
    expect(row.modelDbId, 7);
    expect(row.timestamp, at);
    expect(row.cacheTokens, 4);
    expect(row.cachePrice, 0.5);
    expect(row.spec, isNull, reason: 'a token row leaves all four spec columns NULL');
  });

  test('the range and the page are applied in SQL, newest first', () async {
    for (var day = 1; day <= 5; day++) {
      await usage.recordTokenUsage(
          TokenUsage(taskId: 'd$day', modelId: 'm', timestamp: DateTime(2026, 9, day)));
    }

    final page = await usage.getTokenUsage(
      start: DateTime(2026, 9, 2),
      end: DateTime(2026, 9, 4),
      limit: 2,
      offset: 1,
    );

    expect(page.map((r) => r.taskId), ['d3', 'd2']);
  });

  test('settling a video re-prices the row its submit recorded', () async {
    await usage.recordTokenUsage(TokenUsage(
      taskId: 'video:op-1',
      modelId: 'veo',
      timestamp: at,
      billingMode: 'spec',
      spec: const UsageSpecBilling(
        unit: OutputUnit.second,
        units: 8,
        unitPrice: 0.3,
        snapshot: UsageSpecSnapshot(size: '1080p', seconds: 8),
        inputImages: 1,
        inputUnits: 1,
        inputUnitPrice: 0.05,
      ),
    ));

    final matched = await usage.updateSpecBilling(
      'video:op-1',
      const UsageSpecBilling(
        unit: OutputUnit.second,
        units: 10,
        unitPrice: 0.15,
        snapshot: UsageSpecSnapshot(size: '1080p', seconds: 10),
      ),
    );

    expect(matched, 1);
    final row = (await usage.getTokenUsage()).single;
    // The settle knows the seconds rendered and nothing about what the
    // submit sent: the input columns stay as the submit wrote them.
    expect(row.costParts.spec, closeTo(1.5, 1e-9));
    expect(row.spec!.inputImages, 1);
    expect(row.costParts.specInput, closeTo(0.05, 1e-9));
    expect(row.specLabel, '1080p · 10s');
    expect(await usage.updateSpecBilling('video:nobody', const UsageSpecBilling(units: 1, unitPrice: 1)), 0);
  });

  test('settling leaves what the provider reported the row cost', () async {
    // No video surface reports a price today, but the settle is a partial
    // update of the output four and must stay one: a report on the row is
    // the provider's word, and re-pricing the seconds is not a reason to
    // lose it.
    await usage.recordTokenUsage(TokenUsage(
      taskId: 'video:op-2',
      modelId: 'v',
      timestamp: at,
      billingMode: 'spec',
      spec: const UsageSpecBilling(unit: OutputUnit.second, units: 8, unitPrice: 0.3),
      reportedCost: 1.25,
    ));

    await usage.updateSpecBilling(
      'video:op-2',
      const UsageSpecBilling(unit: OutputUnit.second, units: 10, unitPrice: 0.3),
    );

    final row = (await usage.getTokenUsage()).single;
    expect(row.reportedCost, 1.25);
    expect(row.cost, closeTo(1.25, 1e-9));
    expect(row.snapshotCost, closeTo(3.0, 1e-9));
  });

  test('the latest checkpoint comes back whole', () async {
    expect(await usage.getLatestUsageCheckpoint(), isNull);
    await usage.saveUsageCheckpoint(UsageCheckpoint(timestamp: DateTime(2026, 8, 1), totalCost: 1));
    await usage.saveUsageCheckpoint(UsageCheckpoint(
      timestamp: at,
      totalInputTokens: 10,
      totalCacheTokens: 2,
      totalOutputTokens: 5,
      totalRequestCount: 3,
      totalCost: 1.25,
      groupCosts: const {42: 1.25},
    ));

    final last = (await usage.getLatestUsageCheckpoint())!;

    expect(last.timestamp, at);
    expect(last.totalCacheTokens, 2);
    expect(last.groupCosts, {42: 1.25});
  });

  test('a saved task reads back as the same task', () async {
    final tasks = TaskRepository(db: db);
    await tasks.saveTask(TaskItem(
      id: 't1',
      type: TaskType.videoGenerate,
      imagePaths: const ['a.png'],
      modelId: 'veo',
      modelDbId: 7,
      parameters: const {'prompt': 'p', 'assistantSessionId': 's1'},
      status: TaskStatus.completed,
      resultPaths: const ['out.mp4'],
      operationName: 'op-1',
      createdAt: at,
    ));

    final back = (await tasks.getRecentTasks(10)).single;

    expect(back.id, 't1');
    expect(back.type, TaskType.videoGenerate);
    expect(back.modelDbId, 7);
    expect(back.parameters['prompt'], 'p');
    expect(back.resultPaths, ['out.mp4']);
    expect(back.operationName, 'op-1');
    expect(back.createdAt, at);
    expect((await tasks.getTasksForAssistantSession('s1')).single.id, 't1');
    expect(await tasks.getTasksForAssistantSession('s2'), isEmpty);
  });

  test('a save stores the task as it was when the save was asked for', () async {
    // The queue saves without waiting and then keeps mutating the task.
    final tasks = TaskRepository(db: db);
    final task = TaskItem(
      id: 't2',
      imagePaths: const [],
      modelId: 'm',
      parameters: const {},
      status: TaskStatus.processing,
      createdAt: at,
    );

    final saved = tasks.saveTask(task);
    task.status = TaskStatus.failed;
    await saved;

    expect((await tasks.getRecentTasks(10)).single.status, TaskStatus.processing);
  });

  test('a task that cannot be encoded throws at the call, not into the future', () {
    // Two of the queue's saves are never awaited; an error that only showed
    // up in the returned future would go unhandled there.
    final task = TaskItem(
      id: 't3',
      imagePaths: const [],
      modelId: 'm',
      parameters: {'not json': Object()},
    );

    // Not `expect(() => saveTask(task), throwsA(…))`: handed a closure that
    // returns a future, `throwsA` matches the future's error too, so that
    // spelling stays green when the throw moves into the future.
    Future<void>? returned;
    Object? thrown;
    try {
      returned = TaskRepository(db: db).saveTask(task);
    } catch (e) {
      thrown = e;
    }
    // Only reached with a future when the throw went async; keep its error
    // from escaping the test as an unhandled one.
    returned?.ignore();

    expect(thrown, isA<JsonUnsupportedObjectError>());
    expect(returned, isNull);
  });
}
