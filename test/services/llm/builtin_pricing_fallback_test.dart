import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_config_resolver.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();

  late DatabaseService db;
  late int channelId;

  setUp(() async {
    db = await openTestDatabase();
    channelId = await db.addChannel(
      LLMChannel(
        displayName: 'Test OpenAI',
        type: Vendors.openAIRest,
        endpoint: 'https://api.example.com/v1',
        apiKey: 'sk-test-key',
      ),
    );
  });

  tearDown(() async {
    await closeTestDatabase(db);
  });

  test('falls back to official built-in token pricing when model has no fee group', () async {
    final modelPk = await db.addModel(
      LLMModel(
        modelId: 'openai/gpt-6.2-astra',
        modelName: 'GPT-6.2 Astra',
        tag: 'multimodal',
        channelId: channelId,
      ),
    );

    final config = await LLMConfigResolver(database: db).resolveConfig(modelPk);
    expect(config.pricingKnown, isTrue);
    expect(config.billingMode, 'token');
    expect(config.inputFee, 8.0);
    expect(config.cacheInputFee, 0.4);
    expect(config.outputFee, 40.0);
  });

  test('falls back to official built-in spec pricing for Seedream 5.0 Pro', () async {
    final modelPk = await db.addModel(
      LLMModel(
        modelId: 'doubao-seedream-5-0-pro-260628',
        modelName: 'Seedream 5.0 Pro',
        tag: 'image',
        channelId: channelId,
      ),
    );

    final config = await LLMConfigResolver(database: db).resolveConfig(modelPk);
    expect(config.pricingKnown, isTrue);
    expect(config.billingMode, 'spec');
    expect(config.outputUnit, OutputUnit.image);
    expect(config.outputRates.any((r) => r.size == '2K' && r.price == 0.09), isTrue);
    expect(config.inputUnitFee, 0.003);
    expect(config.inputFreeUnits, 1);
  });

  test('explicit user fee group overrides built-in default pricing', () async {
    final groupId = await db.addPricingGroup(
      PricingGroup(
        name: 'Custom Discount',
        billingMode: 'token',
        inputPrice: 1.25,
        outputPrice: 5.0,
      ),
    );
    final modelPk = await db.addModel(
      LLMModel(
        modelId: 'claude-opus-5-5',
        modelName: 'Claude Opus 5.5',
        tag: 'multimodal',
        channelId: channelId,
        feeGroupId: groupId,
      ),
    );

    final config = await LLMConfigResolver(database: db).resolveConfig(modelPk);
    expect(config.pricingKnown, isTrue);
    expect(config.inputFee, 1.25);
    expect(config.outputFee, 5.0);
  });

  test('unknown model with no fee group remains pricingKnown == false', () async {
    final modelPk = await db.addModel(
      LLMModel(
        modelId: 'my-completely-unknown-model',
        modelName: 'Unknown',
        tag: 'chat',
        channelId: channelId,
      ),
    );

    final config = await LLMConfigResolver(database: db).resolveConfig(modelPk);
    expect(config.pricingKnown, isFalse);
    expect(config.inputFee, 0.0);
    expect(config.outputFee, 0.0);
  });
}
