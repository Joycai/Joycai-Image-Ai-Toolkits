import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The channel probe caps its completion at one token through
/// `options['maxTokens']`, but only ④ read that option — a connection test on
/// ① or ③ paid for a full generation. Both now honour it, and only when it is
/// set: an ordinary request's body is unchanged.
void main() {
  final history = [LLMMessage(role: LLMRole.user, content: 'ping')];

  group('① chat/completions', () {
    Map<String, dynamic> payload(Map<String, dynamic>? options) {
      final config = LLMModelConfig(
        modelId: 'gpt-4o-mini',
        channelType: Vendors.openAIRest,
        endpoint: 'https://example.invalid/v1',
        apiKey: 'k',
      );
      final target = LLMTarget(
        config: config,
        vendor: Vendors.byId(config.channelType),
        model: ModelDescriptor.of(config.modelId),
      );
      return OpenAIChatProtocol().buildChatPayloadForTest(
        target,
        history,
        options: options,
        isStreaming: false,
      );
    }

    // The generic ① profile on a relay host keeps the old spelling; OpenAI's
    // own host takes the new one (its reasoning models 400 on `max_tokens`,
    // so a probe sending it there read as "connected" only by accident). See
    // `VendorProfile.outputCapFieldFor`.
    test('the probe cap reaches the host\'s cap field', () {
      final body = payload(const {'maxTokens': 1});
      expect(body['max_tokens'], 1);
      expect(body.containsKey('max_completion_tokens'), isFalse);
    });

    test('no cap asked for sends neither spelling', () {
      for (final body in [
        payload(null),
        payload(const {'retryCount': 2}),
      ]) {
        expect(body.containsKey('max_tokens'), isFalse);
        expect(body.containsKey('max_completion_tokens'), isFalse);
      }
    });
  });

  group('③ generateContent', () {
    Map<String, dynamic> generationConfig(Map<String, dynamic>? options) =>
        (prepareGooglePayload(history, options, null)['generationConfig'] as Map)
            .cast<String, dynamic>();

    test('the probe cap reaches generationConfig.maxOutputTokens', () {
      expect(generationConfig(const {'maxTokens': 1})['maxOutputTokens'], 1);
    });

    test('no cap asked for sends no maxOutputTokens', () {
      expect(generationConfig(null).containsKey('maxOutputTokens'), isFalse);
      expect(
        generationConfig(const {'aspectRatio': '1:1'}).containsKey('maxOutputTokens'),
        isFalse,
      );
    });
  });
}
