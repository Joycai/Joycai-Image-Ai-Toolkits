import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_distribution.dart';
import 'package:joycai_image_ai_toolkits/core/safety_settings.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  test('all Gemini output modes normalize legacy and malformed snapshots without mutation', () {
    final config = LLMModelConfig(
      modelId: 'gemini-3.1-flash-image',
      channelType: Vendors.newApiOpenAI,
      endpoint: 'https://example.test/v1',
      apiKey: 'synthetic',
    );
    final target = LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
    for (final value in ['OFF', 'BLOCK_NONE', 'BLOCK_ONLY_HIGH', 'BLOCK_LOW_AND_ABOVE', 42]) {
      final raw = {for (final category in SafetySettings.categories) category: value};
      final options = {SafetySettings.paramKey: raw};
      final expected = value == 'BLOCK_LOW_AND_ABOVE' || (AppDistribution.direct && value is String)
          ? value
          : 'BLOCK_MEDIUM_AND_ABOVE';
      for (final images in [false, true]) {
        final payload = prepareGooglePayload([], options, config.endpoint, emitsImages: images);
        expect(
          (payload['safetySettings'] as List).map((row) => row['threshold']),
          everyElement(expected),
        );
      }
      for (final streaming in [false, true]) {
        final payload = prepareOpenAIChatPayload(target, [], options, isStreaming: streaming);
        expect(
          (payload['safety_settings'] as List).map((row) => row['threshold']),
          everyElement(expected),
        );
      }
      // The same snapshot can be retried without rewriting the user's original data.
      expect(raw.values, everyElement(value));
    }
  });

  test('Gemini compatibility payload enforces the same outgoing policy', () {
    final config = LLMModelConfig(
      modelId: 'gemini-3.1-flash-image',
      channelType: Vendors.newApiOpenAI,
      endpoint: 'https://example.test/v1',
      apiKey: 'synthetic',
    );
    final target = LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
    for (final stream in [false, true]) {
      final payload = prepareOpenAIChatPayload(target, [], {
        SafetySettings.paramKey: {for (final c in SafetySettings.categories) c: 'OFF'},
      }, isStreaming: stream);
      expect(
        (payload['safety_settings'] as List).map((e) => e['threshold']),
        everyElement(AppDistribution.direct ? 'OFF' : 'BLOCK_MEDIUM_AND_ABOVE'),
      );
    }
  });
  test('Gemini outgoing payload clamps persisted task thresholds in store builds', () {
    final payload = prepareGooglePayload([], {
      SafetySettings.paramKey: {for (final c in SafetySettings.categories) c: 'OFF'},
    }, 'https://example.test');
    expect(
      (payload['safetySettings'] as List).map((e) => e['threshold']),
      everyElement(AppDistribution.direct ? 'OFF' : 'BLOCK_MEDIUM_AND_ABOVE'),
    );
  });
}
