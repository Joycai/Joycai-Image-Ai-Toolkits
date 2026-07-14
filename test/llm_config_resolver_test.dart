import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_config_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    },
  );

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
  });
}
