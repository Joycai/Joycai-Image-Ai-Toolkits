import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/billing/media_accounting.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  late DatabaseService db;
  late UsageRepository repo;
  setUp(() async {
    db = await openTestDatabase();
    repo = UsageRepository(db: db);
  });
  tearDown(() => closeTestDatabase(db));
  TokenUsage submit() => TokenUsage(
    modelId: 'video',
    taskId: 'video:account:job',
    timestamp: DateTime(2026),
    accounting: MediaAccounting.price(
      PricingGroup(
        name: 'video',
        billingMode: 'spec',
        outputUnit: OutputUnit.second,
        outputRates: const [SpecRate(price: 0.2)],
      ),
      {'input_images': 0, 'input_seconds': 0},
      options: {'seconds': 5},
      video: true,
      pending: true,
    ),
  );
  test('same submit and settlement replay once; history ignores live pricing', () async {
    await repo.recordTokenUsage(submit());
    await repo.recordTokenUsage(submit());
    await db.addPricingGroup(
      PricingGroup(name: 'changed', billingMode: 'spec', outputRates: const [SpecRate(price: 999)]),
    );
    await repo.settleMedia('video:account:job', {'output_seconds': 6.25}, reportedCost: 0.8);
    await repo.settleMedia('video:account:job', {'output_seconds': 6.25}, reportedCost: 0.8);
    final rows = await repo.getTokenUsage();
    expect(rows, hasLength(1));
    expect(rows.single.cost, 0.8);
    expect(rows.single.snapshotCost, 1.25);
    expect(rows.single.accounting!.revision, 1);
  });
  test(
    'transaction failure changes neither components nor reported cost; retry succeeds',
    () async {
      await repo.recordTokenUsage(submit());
      final sql = await db.database;
      await sql.execute(
        "CREATE TRIGGER reject_usage BEFORE UPDATE ON token_usage BEGIN SELECT RAISE(FAIL, 'locked'); END",
      );
      await expectLater(
        repo.settleMedia('video:account:job', {'output_seconds': 8}, reportedCost: 2),
        throwsA(anything),
      );
      final before = (await repo.getTokenUsage()).single;
      expect(before.cost, 1);
      expect(before.reportedCost, isNull);
      await sql.execute('DROP TRIGGER reject_usage');
      await repo.settleMedia('video:account:job', {'output_seconds': 8}, reportedCost: 2);
      expect((await repo.getTokenUsage()).single.snapshotCost, 1.6);
    },
  );
  test('legacy rows without rules are never repriced with current configuration', () async {
    await repo.recordTokenUsage(
      TokenUsage(
        modelId: 'old',
        taskId: 'video:old',
        timestamp: DateTime(2026),
        requestPrice: 3,
        billingMode: 'request',
      ),
    );
    await repo.settleMedia('video:old', {'output_seconds': 9});
    expect((await repo.getTokenUsage()).single.cost, 3);
  });
  test('older settlement cannot replace newer evidence', () async {
    await repo.recordTokenUsage(submit());
    await repo.settleMedia(
      'video:account:job',
      {'output_seconds': 8},
      reportedCost: 2,
      version: 20,
    );
    await repo.settleMedia(
      'video:account:job',
      {'output_seconds': 6},
      reportedCost: 1,
      version: 10,
    );
    final row = (await repo.getTokenUsage()).single;
    expect(row.cost, 2);
    expect(row.snapshotCost, 1.6);
  });
  test('disk journal survives write failure and process-style reopen', () async {
    final root = await Directory.systemTemp.createTemp('joycai-accounting-');
    final path = '${root.path}/isolated.db';
    Future<Database> open() => databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseService.dbVersion,
        onCreate: (db, _) => DatabaseMigration.onCreate(db),
      ),
    );
    var disk = await open();
    try {
      var service = DatabaseService.forDatabase(disk);
      var repository = UsageRepository(db: service);
      await disk.execute(
        "CREATE TRIGGER fail_insert BEFORE INSERT ON token_usage BEGIN SELECT RAISE(FAIL, 'write failure'); END",
      );
      await expectLater(repository.recordTokenUsage(submit()), throwsA(anything));
      final spool = Directory((await service.usageJournalDirectory)!);
      expect(await spool.list().length, 1);
      await disk.execute('DROP TRIGGER fail_insert');
      await disk.close();
      disk = await open();
      service = DatabaseService.forDatabase(disk);
      repository = UsageRepository(db: service);
      await repository.replayPending();
      await repository.replayPending();
      expect(await repository.getTokenUsage(), hasLength(1));
      expect(await spool.list().length, 0);
      await disk.execute(
        "CREATE TRIGGER fail_settle BEFORE UPDATE ON token_usage BEGIN SELECT RAISE(FAIL, 'settlement failure'); END",
      );
      await expectLater(
        repository.settleMedia('video:account:job', {'output_seconds': 7.25}, reportedCost: 0),
        throwsA(anything),
      );
      await disk.execute('DROP TRIGGER fail_settle');
      await repository.replayPending();
      final result = (await repository.getTokenUsage()).single;
      expect(result.cost, 0);
      expect(result.snapshotCost, closeTo(1.45, 1e-12));
    } finally {
      await disk.close();
      await root.delete(recursive: true);
    }
  });
  test('v52 migration is additive and idempotent on old history', () async {
    final sql = await db.database;
    await repo.recordTokenUsage(
      TokenUsage(
        modelId: 'old',
        taskId: 'old',
        timestamp: DateTime(2026),
        inputTokens: 100,
        inputPrice: 2,
      ),
    );
    await sql.execute('ALTER TABLE token_usage DROP COLUMN accounting');
    await sql.execute('ALTER TABLE fee_groups DROP COLUMN media_pricing');
    await sql.execute('DROP TABLE usage_events');
    await DatabaseMigration.migrate(sql, 51, 52);
    await DatabaseMigration.migrate(sql, 51, 52);
    final old = (await repo.getTokenUsage()).single;
    expect(old.accounting, isNull);
    expect(old.cost, 0.0002);
    expect(await sql.query('usage_events'), isEmpty);
  });
}
