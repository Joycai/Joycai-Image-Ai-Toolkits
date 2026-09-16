import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_discovery_service.dart';

/// What a model listing says about a model's limits is read by key shape.
/// Each case is one host's listing as it comes back; a wrong key reads as
/// "unknown" and the row starts unset, which is the silent failure here.
void main() {
  DiscoveredModel listed(Map<String, dynamic> raw) =>
      DiscoveredModel(modelId: 'm', displayName: 'm', rawData: raw);

  test('a bare OpenAI listing reports nothing', () {
    final limits = discoveredLimitsOf(listed({'id': 'gpt-5.6', 'owned_by': 'openai'}));
    expect(limits.contextWindow, isNull);
    expect(limits.maxOutputTokens, isNull);
  });

  test('Anthropic: max_input_tokens and max_tokens', () {
    final limits = discoveredLimitsOf(listed({
      'id': 'claude-opus-5',
      'max_input_tokens': 1000000,
      'max_tokens': 128000,
    }));
    expect(limits.contextWindow, 1000000);
    expect(limits.maxOutputTokens, 128000);
  });

  test('Gemini: inputTokenLimit and outputTokenLimit', () {
    final limits = discoveredLimitsOf(listed({
      'name': 'models/gemini-3.1-pro',
      'inputTokenLimit': 1048576,
      'outputTokenLimit': 65536,
    }));
    expect(limits.contextWindow, 1048576);
    expect(limits.maxOutputTokens, 65536);
  });

  test('OpenRouter: context_length and top_provider.max_completion_tokens', () {
    final limits = discoveredLimitsOf(listed({
      'id': 'openai/gpt-5.6',
      'context_length': 400000,
      'top_provider': {'context_length': 400000, 'max_completion_tokens': 128000},
    }));
    expect(limits.contextWindow, 400000);
    expect(limits.maxOutputTokens, 128000);
  });

  test('LM Studio: max_context_length, no cap', () {
    final limits = discoveredLimitsOf(listed({'id': 'qwen3-8b', 'max_context_length': 32768}));
    expect(limits.contextWindow, 32768);
    expect(limits.maxOutputTokens, isNull);
  });

  test('zero, negative and junk read as unknown; numeric strings count', () {
    expect(discoveredLimitsOf(listed({'max_tokens': 0})).maxOutputTokens, isNull);
    expect(discoveredLimitsOf(listed({'max_tokens': -1})).maxOutputTokens, isNull);
    expect(discoveredLimitsOf(listed({'max_tokens': 'lots'})).maxOutputTokens, isNull);
    expect(discoveredLimitsOf(listed({'max_tokens': '65536'})).maxOutputTokens, 65536);
    expect(discoveredLimitsOf(listed({'top_provider': 'n/a'})).maxOutputTokens, isNull);
  });
}
