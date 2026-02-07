import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_config_resolver.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_models.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/services.dart';
import 'dart:io';

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

      final feeGroupId = await db.addFeeGroup({
        'name': 'Test Fee',
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
        'fee_group_id': feeGroupId,
      });

      final resolver = LLMConfigResolver();
      final config = await resolver.resolveConfig(modelPk);

      expect(config.modelId, 'test-model-1');
      expect(config.endpoint, 'https://test.com');
      expect(config.inputFee, 0.5);
      expect(config.outputFee, 1.0);
    });
  });
}
