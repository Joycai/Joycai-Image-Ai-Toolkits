import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// MiniMax's ① face thinks by default and is switched by a top-level
/// `thinking: {type: adaptive | disabled}` (docs/api/minimax.md §1).
/// Live, 2026-09-19 (api.minimaxi.com, MiniMax-M3): `reasoning_effort:
/// "none"` is accepted and ignored — 34 reasoning tokens, billed — while
/// `{type: "disabled"}` answers with none; `{type: "enabled"}` (DeepSeek's
/// spelling) is a 400 naming the two allowed values.
void main() {
  Map<String, dynamic> payload(ReasoningEffort? effort) {
    final config = LLMModelConfig(
      modelId: 'MiniMax-M3',
      channelType: Vendors.minimax,
      endpoint: 'https://api.minimaxi.com/v1',
      apiKey: 'k',
      enableThinking: effort != null,
      reasoningEffort: effort,
    );
    return OpenAIChatProtocol().buildChatPayloadForTest(
      LLMTarget(
        config: config,
        vendor: Vendors.byId(Vendors.minimax),
        model: ModelDescriptor.of('MiniMax-M3'),
      ),
      [LLMMessage(role: LLMRole.user, content: 'hi')],
      isStreaming: false,
    );
  }

  test('off sends the disabled object and no reasoning_effort', () {
    final body = payload(ReasoningEffort.off);
    expect(body['thinking'], {'type': 'disabled'});
    expect(body.containsKey('reasoning_effort'), isFalse);
  });

  test('any level above off is adaptive, with no intensity', () {
    for (final effort in [ReasoningEffort.medium, ReasoningEffort.high]) {
      final body = payload(effort);
      expect(body['thinking'], {'type': 'adaptive'}, reason: '$effort');
      expect(body.containsKey('reasoning_effort'), isFalse);
    }
  });

  test('the default sends nothing', () {
    final body = payload(null);
    expect(body.containsKey('thinking'), isFalse);
    expect(body.containsKey('reasoning_effort'), isFalse);
  });

  test('the editor offers a switch, not a ladder', () {
    expect(
      LLMDispatcher.reasoningLadder(
          channelType: Vendors.minimax, modelId: 'MiniMax-M3'),
      const <ReasoningEffort?>[null, ReasoningEffort.off, ReasoningEffort.medium],
    );
  });
}
