import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The model editor's reasoning slider offers only the rungs that change the
/// request. A rung that sends what its neighbour sends is a knob whose only
/// effect is nothing, so these pin, wire by wire, which rungs each one tells
/// apart — and that a model whose requests never carry reasoning has none.
void main() {
  List<ReasoningEffort?> ladder(String channelType, String modelId, {String? tag}) =>
      LLMDispatcher.reasoningLadder(channelType: channelType, modelId: modelId, tag: tag);

  const full = <ReasoningEffort?>[
    null,
    ReasoningEffort.off,
    ReasoningEffort.low,
    ReasoningEffort.medium,
    ReasoningEffort.high,
    ReasoningEffort.max,
  ];

  test('the OpenAI wire sends every rung as its own value', () {
    expect(ladder(Vendors.openAIRest, 'gpt-5'), full);
    expect(ladder(Vendors.newApiOpenAI, 'o3-mini'), full);
    // DeepSeek spells off as the thinking object, but it is still its own request.
    expect(ladder(Vendors.deepseek, 'deepseek-chat'), full);
    // Bailian's compatible face is the OpenAI wire, whatever its ④ face declares.
    expect(ladder(Vendors.dashscope, 'qwen-plus'), full);
  });

  test('current Claude has no Off: it withholds thinking exactly as Default does', () {
    const adaptive = <ReasoningEffort?>[
      null,
      ReasoningEffort.low,
      ReasoningEffort.medium,
      ReasoningEffort.high,
      ReasoningEffort.max,
    ];
    expect(ladder(Vendors.anthropicRest, 'claude-opus-4-7'), adaptive);
    expect(ladder(Vendors.newApiAnthropic, 'claude-opus-5'), adaptive);
  });

  test('a thinking switch with no intensity is Default and one on rung', () {
    const binary = <ReasoningEffort?>[null, ReasoningEffort.medium];
    // Claude 4.5 and earlier only know the budget form.
    expect(ladder(Vendors.anthropicRest, 'claude-sonnet-4-5-20250929'), binary);
    expect(ladder(Vendors.newApiAnthropic, 'claude-3-7-sonnet-latest'), binary);
    // MiniMax's bare adaptive object.
    expect(ladder(Vendors.minimaxAnthropic, 'MiniMax-M3'), binary);
  });

  test('DashScope native is Default, an explicit Off, and on', () {
    expect(ladder(Vendors.dashscopeNative, 'qwen3-max'),
        <ReasoningEffort?>[null, ReasoningEffort.off, ReasoningEffort.medium]);
  });

  test('wires that ignore reasoning offer no rung', () {
    expect(ladder(Vendors.googleRest, 'gemini-2.5-pro'), isEmpty);
    expect(ladder(Vendors.newApiGemini, 'gemini-2.5-flash'), isEmpty);
    expect(ladder(Vendors.midjourneyProxy, 'midjourney'), isEmpty);
  });

  test('a model whose kind does not go down chat offers no rung', () {
    expect(ladder(Vendors.openAIRest, 'gpt-5', tag: 'image'), isEmpty);
    expect(ladder(Vendors.anthropicRest, 'claude-opus-4-7', tag: 'video'), isEmpty);
    expect(ladder(Vendors.openAIRest, 'gpt-5', tag: 'multimodal'), full);
  });
}
