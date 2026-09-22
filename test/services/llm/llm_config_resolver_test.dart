import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_config_resolver.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();

  group('LLMConfigResolver (Integration-lite)', () {
    // Injected rather than the default service: these tests only need a
    // database of the right shape, and one they own outright cannot contend
    // with a neighbouring test file for the shared file's write lock.
    late DatabaseService db;

    setUp(() async => db = await openTestDatabase());
    tearDown(() async => closeTestDatabase(db));

    test('should resolve config from database', () async {
      // Setup mock data in the in-memory DB
      final channelId = await db.addChannel(LLMChannel(
        displayName: 'Test Channel',
        type: 'openai-api',
        endpoint: 'https://test.com',
        apiKey: 'key-123',
      ));

      final pricingGroupId = await db.addPricingGroup(PricingGroup(
        name: 'Test Pricing',
        billingMode: 'token',
        inputPrice: 0.5,
        outputPrice: 1.0,
      ));

      final modelPk = await db.addModel(LLMModel(
        modelId: 'test-model-1',
        modelName: 'Test Model',
        tag: 'chat',
        channelId: channelId,
        feeGroupId: pricingGroupId,
      ));

      final resolver = LLMConfigResolver(database: db);
      final config = await resolver.resolveConfig(modelPk);

      expect(config.modelId, 'test-model-1');
      expect(config.endpoint, 'https://test.com');
      expect(config.inputFee, 0.5);
      expect(config.outputFee, 1.0);
      // The group left the cache rate unset, so cache hits bill as plain input.
      expect(config.cacheInputFee, isNull);
      expect(config.effectiveCacheInputFee, 0.5);
    });

    test('resolves a configured cache rate, keeping 0.0 distinct from unset', () async {
      final channelId = await db.addChannel(LLMChannel(
        displayName: 'Cache Channel',
        type: 'openai-api',
        endpoint: 'https://cache.test',
        apiKey: 'key-cache',
      ));

      final freeCacheGroup = await db.addPricingGroup(PricingGroup(
        name: 'Free Cache',
        billingMode: 'token',
        inputPrice: 2.0,
        cacheInputPrice: 0.0,
        outputPrice: 8.0,
      ));
      final discountGroup = await db.addPricingGroup(PricingGroup(
        name: 'Discounted Cache',
        billingMode: 'token',
        inputPrice: 2.0,
        cacheInputPrice: 0.25,
        outputPrice: 8.0,
      ));

      Future<void> expectCacheFee(int groupId, String modelId, double expected) async {
        final modelPk = await db.addModel(LLMModel(
          modelId: modelId,
          modelName: modelId,
          tag: 'chat',
          channelId: channelId,
          feeGroupId: groupId,
        ));
        final config = await LLMConfigResolver(database: db).resolveConfig(modelPk);
        expect(config.effectiveCacheInputFee, expected);
      }

      // An explicit 0.0 must survive the round trip as a real free-cache rate
      // and not decay into "unset", which would bill it at the input price.
      await expectCacheFee(freeCacheGroup, 'free-cache-model', 0.0);
      await expectCacheFee(discountGroup, 'discount-cache-model', 0.25);
    });

    test('a spec group\'s input-image rate reaches the config', () async {
      final channelId = await db.addChannel(LLMChannel(
        displayName: 'Ark',
        type: 'openai-api',
        endpoint: 'https://ark.test',
        apiKey: 'key-ark',
      ));
      final groupId = await db.addPricingGroup(PricingGroup(
        name: 'Seedream pro',
        billingMode: 'spec',
        inputUnitPrice: 0.02,
        inputFreeUnits: 1,
      ));
      final modelPk = await db.addModel(LLMModel(
        modelId: 'doubao-seedream-5-0-pro',
        modelName: 'Seedream pro',
        tag: 'image',
        channelId: channelId,
        feeGroupId: groupId,
      ));

      final config = await LLMConfigResolver(database: db).resolveConfig(modelPk);

      expect(config.inputUnitFee, 0.02);
      expect(config.inputFreeUnits, 1);
    });

    test('a per-second and a request group\'s input-image rate reach the config; a token group\'s does not', () async {
      final channelId = await db.addChannel(LLMChannel(
        displayName: 'xAI',
        type: 'xai-api',
        endpoint: 'https://api.x.ai/v1',
        apiKey: 'key-xai',
      ));
      Future<LLMModelConfig> configOf(PricingGroup group) async {
        final groupId = await db.addPricingGroup(group);
        final modelPk = await db.addModel(LLMModel(
          modelId: 'grok-imagine-video-1.5-${group.name}',
          modelName: group.name,
          tag: 'video',
          channelId: channelId,
          feeGroupId: groupId,
        ));
        return LLMConfigResolver(database: db).resolveConfig(modelPk);
      }

      final perSecond = await configOf(PricingGroup(
        name: 'sec',
        billingMode: 'spec',
        outputUnit: OutputUnit.second,
        inputUnitPrice: 0.01,
      ));
      final perRequest = await configOf(PricingGroup(
        name: 'req',
        billingMode: 'request',
        requestPrice: 0.08,
        inputUnitPrice: 0.01,
        inputFreeUnits: 1,
      ));
      final token = await configOf(PricingGroup(
        name: 'tok',
        billingMode: 'token',
        inputUnitPrice: 0.01,
      ));

      expect(perSecond.inputUnitFee, 0.01);
      expect(perRequest.inputUnitFee, 0.01);
      expect(perRequest.inputFreeUnits, 1);
      expect(token.inputUnitFee, 0.0, reason: 'a token group never charges inputs');
      expect(token.inputFreeUnits, 0);
    });

    test('deleting a channel deletes its models without leaving orphans', () async {
      final channelId = await db.addChannel(LLMChannel(
        displayName: 'Disposable Channel',
        type: 'openai-api-rest',
        endpoint: 'https://disposable.com/v1',
        apiKey: 'key-xyz',
      ));
      await db.addModel(LLMModel(
        modelId: 'doomed-model',
        modelName: 'Doomed',
        tag: 'image',
        channelId: channelId,
      ));

      expect((await db.getModels()).where((m) => m.channelId == channelId), isNotEmpty);

      await db.deleteChannel(channelId);

      final remaining = await db.getModels();
      // The model must be gone — not merely orphaned (channel_id == null), which
      // is what previously leaked a "ghost" channel into the workbench selector.
      expect(remaining.where((m) => m.modelId == 'doomed-model'), isEmpty);
      expect(remaining.where((m) => m.channelId == null), isEmpty);
    });

    test('a missing model is a typed config error, not a bare Exception',
        () async {
      await expectLater(
        LLMConfigResolver(database: db).resolveConfig(987654),
        throwsA(isA<LLMConfigException>().having(
            (e) => e.kind, 'kind', LLMConfigErrorKind.modelNotFound)),
      );
    });

    test('a keyed channel saved without a key fails before any request',
        () async {
      final channelId = await db.addChannel(LLMChannel(
        displayName: 'Keyless Relay',
        type: 'openai-api-rest',
        endpoint: 'https://keyless.test/v1',
        apiKey: '',
      ));
      final modelPk = await db.addModel(LLMModel(
        modelId: 'keyless-model',
        modelName: 'Keyless',
        tag: 'chat',
        channelId: channelId,
      ));
      await expectLater(
        LLMConfigResolver(database: db).resolveConfig(modelPk),
        throwsA(isA<LLMConfigException>()
            .having((e) => e.kind, 'kind', LLMConfigErrorKind.missingApiKey)
            .having((e) => e.message, 'message', contains('Keyless Relay'))),
      );
    });
  });

  // B8: a channel saved without an API key used to send a keyless request and
  // surface the provider's bare 401. The resolver now refuses it up front with
  // a typed error naming the channel — except for vendors that declare they
  // work keyless (standard 11 §D39).
  group('LLMConfigResolver.requireApiKey', () {
    test('a keyed vendor with no key is a typed config error naming the channel',
        () {
      expect(
        () => LLMConfigResolver.requireApiKey(
          channelType: Vendors.openAIRest,
          apiKey: '',
          channelName: 'My Relay',
          modelId: 'gpt-4o',
        ),
        throwsA(isA<LLMConfigException>()
            .having((e) => e.kind, 'kind', LLMConfigErrorKind.missingApiKey)
            .having((e) => e.message, 'message', contains('My Relay'))),
      );
    });

    test('a whitespace-only key counts as missing', () {
      expect(
        () => LLMConfigResolver.requireApiKey(
          channelType: Vendors.anthropicRest,
          apiKey: '   ',
          channelName: 'Claude',
          modelId: 'claude-sonnet-4-5',
        ),
        throwsA(isA<LLMConfigException>()),
      );
    });

    test('keyless local runtimes are allowed through', () {
      for (final type in [Vendors.ollama, Vendors.lmStudio, Vendors.minimaxH3Base]) {
        expect(
          () => LLMConfigResolver.requireApiKey(
            channelType: type,
            apiKey: '',
            channelName: 'local',
            modelId: 'llama3',
          ),
          returnsNormally,
          reason: type,
        );
      }
    });

    test('a present key passes', () {
      expect(
        () => LLMConfigResolver.requireApiKey(
          channelType: Vendors.openAIRest,
          apiKey: 'sk-x',
          channelName: 'c',
          modelId: 'm',
        ),
        returnsNormally,
      );
    });

    test('config errors are never retried', () {
      expect(
          LLMService.isRetryable(const LLMConfigException(
              LLMConfigErrorKind.missingApiKey, 'no key')),
          isFalse);
    });
  });
}
