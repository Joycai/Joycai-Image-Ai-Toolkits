import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/media_pricing.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/image_batch_session.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  tearDown(() => LLMService.usageSinkOverride = null);
  test('immediate and Batch share modality validation, cache math and costs', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));
    final usage = {
      'input_tokens': 300,
      'output_tokens': 100,
      'input_tokens_details': {
        'text_tokens': 100,
        'image_tokens': 200,
        'cached_tokens': 30,
        'cached_tokens_details': {'text_tokens': 10, 'image_tokens': 20},
      },
    };
    final rows = <TokenUsage>[];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    await LLMService(database: db).recordUsageForTest(
      LLMModelConfig(
        modelId: 'image',
        channelType: 'openai-api-rest',
        endpoint: 'https://unused.invalid',
        apiKey: 'unused',
        inputFee: 2.5,
        cacheInputFee: 0.625,
        outputFee: 15,
        mediaPricing: const MediaPricing(imageInput: 4, imageCache: 1, imageOutput: 15),
      ),
      {...usage, 'image_token_output': true},
    );
    await ImageBatchSession.settle(
      db,
      'test',
      null,
      {
        'modelId': 'image',
        'submittedAt': DateTime(2026).toIso8601String(),
        'textInputRate': 2.5,
        'textCacheRate': 0.625,
        'imageInputRate': 4,
        'imageCacheRate': 1,
        'outputRate': 15,
      },
      {'usage': usage},
    );
    final batch = (await db.getTokenUsage()).single;
    expect(batch.cost, rows.single.cost);
    expect(batch.inputTokens, rows.single.inputTokens);
    expect(batch.outputTokens, rows.single.outputTokens);
    expect(batch.inputPrice, rows.single.inputPrice);
    expect(batch.cachePrice, rows.single.cachePrice);
    expect(batch.outputPrice, rows.single.outputPrice);
    expect(
      batch.accounting!.components.map((c) => c.toMap()).toList(),
      rows.single.accounting!.components.map((c) => c.toMap()).toList(),
    );
    expect(rows.single.cacheTokens, 30);
  });
  test('unknown immediate usage stays incomplete rather than actual free', () async {
    final rows = <TokenUsage>[];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    await LLMService().recordUsageForTest(
      LLMModelConfig(
        modelId: 'i',
        channelType: 'openai-api-rest',
        endpoint: 'https://unused.invalid',
        apiKey: 'unused',
      ),
      {'image_token_output': true},
    );
    expect(rows.single.costIncomplete, isTrue);
    expect(rows.single.accounting!.components.any((c) => c.quantity == null), isTrue);
  });

  test('Batch merges partial evidence using the original prices and one row', () async {
    final db = await openTestDatabase();
    addTearDown(() => closeTestDatabase(db));
    final state = <String, dynamic>{
      'modelId': 'image',
      'submittedAt': DateTime(2026).toIso8601String(),
      'textInputRate': 2.5,
      'textCacheRate': 0.625,
      'imageInputRate': 4,
      'imageCacheRate': 1,
      'outputRate': 15,
    };
    await expectLater(
      ImageBatchSession.settle(db, 'partial', null, state, {
        'usage': {
          'input_tokens': 300,
          'input_tokens_details': {'text_tokens': 100, 'image_tokens': 200, 'cached_tokens': 0},
        },
      }),
      throwsA(isA<LLMApiException>()),
    );
    await ImageBatchSession.settle(
      db,
      'partial',
      null,
      {...state, 'outputRate': 999},
      {
        'usage': {'output_tokens': 100},
      },
    );
    final row = (await db.getTokenUsage()).single;
    expect(row.costIncomplete, isFalse);
    expect(row.cost, closeTo(0.00255, 1e-10));
    expect(row.inputTokens, 300);
    expect(row.outputTokens, 100);
  });
}
