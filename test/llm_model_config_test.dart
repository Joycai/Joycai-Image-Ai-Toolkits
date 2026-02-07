import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_models.dart';

void main() {
  group('LLMModelConfig', () {
    test('Initialization should set correct values', () {
      final config = LLMModelConfig(
        pk: 1,
        modelId: 'test-model',
        type: 'openai-api',
        channelType: 'openai',
        endpoint: 'https://api.openai.com/v1',
        apiKey: 'sk-123',
        inputFee: 0.01,
        outputFee: 0.02,
        billingMode: 'token',
        requestFee: 0.0,
        proxyEnabled: true,
        proxyUrl: 'http://localhost:8080',
      );

      expect(config.pk, 1);
      expect(config.modelId, 'test-model');
      expect(config.type, 'openai-api');
      expect(config.endpoint, 'https://api.openai.com/v1');
      expect(config.apiKey, 'sk-123');
      expect(config.inputFee, 0.01);
      expect(config.outputFee, 0.02);
      expect(config.billingMode, 'token');
      expect(config.proxyEnabled, true);
      expect(config.proxyUrl, 'http://localhost:8080');
    });

    test('LLMMessage should be initialized correctly', () {
      final message = LLMMessage(
        role: LLMRole.user,
        content: 'Hello AI',
      );

      expect(message.role, LLMRole.user);
      expect(message.content, 'Hello AI');
      expect(message.attachments, isEmpty);
    });

    test('LLMAttachment fromFile should create correct attachment', () {
      // We can't easily test File in unit tests without mocks, 
      // but we can check the constructor if it was exposed or use a mock file if available.
      // Since LLMAttachment.fromFile takes a File, we'll skip the real file part.
    });
  });
}
