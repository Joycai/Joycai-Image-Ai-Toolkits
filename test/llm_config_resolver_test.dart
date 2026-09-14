import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_config_resolver.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  usePrivateDataDir('joycai_config_resolver_test');

  group('LLMConfigResolver (Integration-lite)', () {
    test('should resolve config from database', () async {
      final db = DatabaseService();
      // Setup mock data in the in-memory DB
      final channelId = await db.addChannel({
        'display_name': 'Test Channel',
        'type': 'openai-api',
        'endpoint': 'https://test.com',
        'api_key': 'key-123',
      });

      final pricingGroupId = await db.addPricingGroup({
        'name': 'Test Pricing',
        'billing_mode': 'token',
        'input_price': 0.5,
        'output_price': 1.0,
      });

      final modelPk = await db.addModel({
        'model_id': 'test-model-1',
        'model_name': 'Test Model',
        'type': 'chat',
        'tag': 'chat',
        'channel_id': channelId,
        'fee_group_id': pricingGroupId,
      });

      final resolver = LLMConfigResolver();
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
      final db = DatabaseService();
      final channelId = await db.addChannel({
        'display_name': 'Cache Channel',
        'type': 'openai-api',
        'endpoint': 'https://cache.test',
        'api_key': 'key-cache',
      });

      final freeCacheGroup = await db.addPricingGroup({
        'name': 'Free Cache',
        'billing_mode': 'token',
        'input_price': 2.0,
        'cache_input_price': 0.0,
        'output_price': 8.0,
      });
      final discountGroup = await db.addPricingGroup({
        'name': 'Discounted Cache',
        'billing_mode': 'token',
        'input_price': 2.0,
        'cache_input_price': 0.25,
        'output_price': 8.0,
      });

      Future<void> expectCacheFee(int groupId, String modelId, double expected) async {
        final modelPk = await db.addModel({
          'model_id': modelId,
          'model_name': modelId,
          'type': 'chat',
          'tag': 'chat',
          'channel_id': channelId,
          'fee_group_id': groupId,
        });
        final config = await LLMConfigResolver().resolveConfig(modelPk);
        expect(config.effectiveCacheInputFee, expected);
      }

      // An explicit 0.0 must survive the round trip as a real free-cache rate
      // and not decay into "unset", which would bill it at the input price.
      await expectCacheFee(freeCacheGroup, 'free-cache-model', 0.0);
      await expectCacheFee(discountGroup, 'discount-cache-model', 0.25);
    });

    test('deleting a channel deletes its models without leaving orphans', () async {
      final db = DatabaseService();
      final channelId = await db.addChannel({
        'display_name': 'Disposable Channel',
        'type': 'openai-api-rest',
        'endpoint': 'https://disposable.com/v1',
        'api_key': 'key-xyz',
      });
      await db.addModel({
        'model_id': 'doomed-model',
        'model_name': 'Doomed',
        'type': 'openai-api',
        'tag': 'image',
        'channel_id': channelId,
      });

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
        LLMConfigResolver().resolveConfig(987654),
        throwsA(isA<LLMConfigException>().having(
            (e) => e.kind, 'kind', LLMConfigErrorKind.modelNotFound)),
      );
    });

    test('a keyed channel saved without a key fails before any request',
        () async {
      final db = DatabaseService();
      final channelId = await db.addChannel({
        'display_name': 'Keyless Relay',
        'type': 'openai-api-rest',
        'endpoint': 'https://keyless.test/v1',
        'api_key': '',
      });
      final modelPk = await db.addModel({
        'model_id': 'keyless-model',
        'model_name': 'Keyless',
        'tag': 'chat',
        'channel_id': channelId,
      });
      await expectLater(
        LLMConfigResolver().resolveConfig(modelPk),
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
