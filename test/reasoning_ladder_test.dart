import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The model editor's reasoning slider offers only the rungs that change the
/// request. A rung that sends what its neighbour sends is a knob whose only
/// effect is nothing, so these pin, wire by wire, which rungs each one tells
/// apart — and that a model whose requests never carry reasoning has none.
void main() {
  List<ReasoningEffort?> ladder(String channelType, String modelId,
          {String? tag, String? wireProtocol}) =>
      LLMDispatcher.reasoningLadder(
          channelType: channelType,
          modelId: modelId,
          tag: tag,
          wireProtocol: wireProtocol);

  const full = <ReasoningEffort?>[
    null,
    ReasoningEffort.off,
    ReasoningEffort.low,
    ReasoningEffort.medium,
    ReasoningEffort.high,
    ReasoningEffort.max,
  ];

  // A switch with no intensity: Default (send nothing), an explicit Off, on.
  const onOff = <ReasoningEffort?>[
    null,
    ReasoningEffort.off,
    ReasoningEffort.medium,
  ];

  test('the OpenAI wire sends every rung as its own value', () {
    expect(ladder(Vendors.openAIRest, 'gpt-5'), full);
    expect(ladder(Vendors.newApiOpenAI, 'o3-mini'), full);
    // DeepSeek spells off as the thinking object, but it is still its own request.
    expect(ladder(Vendors.deepseek, 'deepseek-chat'), full);
  });

  test("Bailian's compatible face is the enable_thinking switch", () {
    // Declared per face (03 §3 switch dialect): the ① face sends a boolean and
    // no reasoning_effort, so its intensities are one request.
    expect(ladder(Vendors.dashscope, 'qwen-plus'), onOff);
  });

  group('the ladder follows the chat face routing resolves', () {
    test('a compatible-mode channel pinned to the ④ face', () {
      // Bailian's ④ face takes the manual budget form: on or off.
      expect(
          ladder(Vendors.dashscope, 'qwen-plus', wireProtocol: 'anthropic-chat'),
          const <ReasoningEffort?>[null, ReasoningEffort.medium]);
    });

    test('a native channel pinned to the ① face', () {
      expect(
          ladder(Vendors.dashscopeNative, 'qwen3-max',
              wireProtocol: 'openai-chat'),
          onOff);
    });

    test('a compatible-mode channel pinned to the native face', () {
      expect(
          ladder(Vendors.dashscope, 'qwen3-max', wireProtocol: 'dashscope-chat'),
          onOff);
    });

    test('a stale or off-menu pin reads as auto, exactly as routing does', () {
      expect(
          ladder(Vendors.dashscope, 'qwen-plus', wireProtocol: 'quantum-chat'),
          onOff);
      // The generic ① vendor has no ④ face to pin.
      expect(
          ladder(Vendors.openAIRest, 'gpt-5', wireProtocol: 'anthropic-chat'),
          full);
    });
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

  test('Gemini offers the rungs thinkingConfig tells apart: Max is High', () {
    const gemini = <ReasoningEffort?>[
      null,
      ReasoningEffort.off,
      ReasoningEffort.low,
      ReasoningEffort.medium,
      ReasoningEffort.high,
    ];
    // thinkingLevel (Gemini 3+), and the guess for an id with no version.
    expect(ladder(Vendors.officialGoogle, 'gemini-3-pro-preview'), gemini);
    expect(ladder(Vendors.newApiGemini, 'my-relay-model'), gemini);
    // thinkingBudget (Gemini 2.5).
    expect(ladder(Vendors.googleRest, 'gemini-2.5-pro'), gemini);
    expect(ladder(Vendors.newApiGemini, 'gemini-2.5-flash'), gemini);
  });

  test('wires and models that ignore reasoning offer no rung', () {
    // A Gemini that does not think takes no thinkingConfig at all.
    expect(ladder(Vendors.officialGoogle, 'gemini-2.0-flash'), isEmpty);
    expect(ladder(Vendors.midjourneyProxy, 'midjourney'), isEmpty);
  });

  test('a model whose kind does not go down chat offers no rung', () {
    expect(ladder(Vendors.openAIRest, 'gpt-5', tag: 'image'), isEmpty);
    expect(ladder(Vendors.anthropicRest, 'claude-opus-4-7', tag: 'video'), isEmpty);
    expect(ladder(Vendors.openAIRest, 'gpt-5', tag: 'multimodal'), full);
  });
}
