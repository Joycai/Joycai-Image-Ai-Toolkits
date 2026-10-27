import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/billing/media_accounting.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// A video is billed at submit by the seconds it asked for; once the job is
/// done, the seconds the provider reports it rendered correct that row. A
/// wan `duration: -1` ("let the model decide") asked for none and used to be
/// billed zero seconds. Where the terminal poll also says what the job cost
/// (xAI), that figure lands on the row too, under every billing mode.
void main() {
  sqfliteFfiInit();
  group('videoDoneEnvelope', () {
    test('carries a reported length', () {
      final done = videoDoneEnvelope(
        'op',
        'https://x/v.mp4',
        requiresAuth: false,
        renderedSeconds: 7,
      );
      expect(done[videoRenderedSecondsKey], 7);
      expect(
        videoDoneEnvelope(
          'op',
          'u',
          requiresAuth: false,
          renderedSeconds: '5',
        )[videoRenderedSecondsKey],
        5,
      );
    });

    test('an absent length is unknown and a reported zero survives', () {
      expect(
        videoDoneEnvelope('op', 'u', requiresAuth: false).containsKey(videoRenderedSecondsKey),
        isFalse,
      );
      expect(
        videoDoneEnvelope(
          'op',
          'u',
          requiresAuth: false,
          renderedSeconds: 0,
        ).containsKey(videoRenderedSecondsKey),
        isTrue,
      );
    });

    test('carries a reported cost under the images protocols\' key', () {
      final done = videoDoneEnvelope('op', 'u', requiresAuth: false, reportedCost: 0.09);
      expect(reportedCostOf(done), 0.09);
      expect(
        videoDoneEnvelope('op', 'u', requiresAuth: false).containsKey(reportedCostKey),
        isFalse,
      );
      expect(
        videoDoneEnvelope(
          'op',
          'u',
          requiresAuth: false,
          reportedCost: -1,
        ).containsKey(reportedCostKey),
        isFalse,
      );
      expect(
        reportedCostOf(videoDoneEnvelope('op', 'u', requiresAuth: false, reportedCost: 0)),
        0,
        reason: 'a reported zero is a report',
      );
    });
  });

  group('settleVideoUsage', () {
    late DatabaseService database;
    setUp(() async {
      database = await openTestDatabase();
    });
    tearDown(() async {
      LLMService.configResolverOverride = null;
      await closeTestDatabase(database);
    });
    test('uses submitted rules and atomically retains inputs and zero quote', () async {
      final row = TokenUsage(
        modelId: 'video',
        taskId: 'video:job',
        timestamp: DateTime(2026),
        accounting: MediaAccounting.price(
          PricingGroup(
            name: 'old',
            billingMode: 'spec',
            outputUnit: OutputUnit.second,
            outputRates: const [SpecRate(price: 0.2)],
            inputUnitPrice: 0.01,
          ),
          {'input_images': 2, 'input_seconds': 0},
          options: {'seconds': 5},
          video: true,
          pending: true,
        ),
      );
      await database.recordTokenUsage(row);
      LLMService.configResolverOverride = (_) => throw StateError('must never read current prices');
      await LLMService(database: database).settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'job',
        renderedSeconds: 6.25,
        reportedCost: 0,
      );
      final result = (await database.getTokenUsage()).single;
      expect(result.cost, 0);
      expect(result.snapshotCost, closeTo(1.27, 1e-12));
      expect(result.accounting!.quantities['input_images'], 2);
    });
    test('missing submit row never creates a zero-cost final record', () async {
      await LLMService(database: database).settleVideoUsage(
        modelIdentifier: 1,
        operationName: 'absent',
        renderedSeconds: 6,
        reportedCost: 1,
      );
      expect(await database.getTokenUsage(), isEmpty);
    });
  });
}
