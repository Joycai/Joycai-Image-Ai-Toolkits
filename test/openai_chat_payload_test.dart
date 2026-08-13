import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the ①-family request/response rules the compat-layer fixes rest on:
/// reasoning echo-back (reasoning.md §3), inline `<think>` separation
/// (landscape.md MiniMax sample), and the two in-body error envelopes
/// (streaming.md §3.1/§3.2).
void main() {
  LLMTarget target(String modelId) {
    final config = LLMModelConfig(
      modelId: modelId,
      channelType: Vendors.openAIRest,
      endpoint: 'https://api.example.com/v1',
      apiKey: 'k',
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
  }

  group('stripInlineThink', () {
    test('text without tags passes through untouched', () {
      final r = stripInlineThink('a plain answer');
      expect(r.text, 'a plain answer');
      expect(r.reasoning, isNull);
    });

    test('separates the MiniMax default shape', () {
      final r = stripInlineThink('<think>let me consider…</think>\n\n正式回答');
      expect(r.text, '正式回答');
      expect(r.reasoning, 'let me consider…');
    });

    test('multiple spans are all collected', () {
      final r = stripInlineThink('<think>a</think>one<think>b</think>two');
      expect(r.text, 'onetwo');
      expect(r.reasoning, 'ab');
    });

    test('an unterminated span swallows the rest as reasoning, not text', () {
      final r = stripInlineThink('answer so far<think>and I was cut off');
      expect(r.text, 'answer so far');
      expect(r.reasoning, 'and I was cut off');
    });
  });

  group('InlineThinkStreamFilter', () {
    test('a tag split across chunks is reassembled — <thi + nk> is normal', () {
      final f = InlineThinkStreamFilter();
      final a = f.feed('hello <thi');
      final b = f.feed('nk>secret</th');
      final c = f.feed('ink> world');
      final flush = f.flush();

      final text = a.text + b.text + c.text + flush.text;
      final reasoning = a.reasoning + b.reasoning + c.reasoning + flush.reasoning;
      expect(text, 'hello  world');
      expect(reasoning, 'secret');
    });

    test('plain text streams through without buffering distortion', () {
      final f = InlineThinkStreamFilter();
      final out = f.feed('no tags here');
      expect(out.text, 'no tags here');
      expect(out.reasoning, isEmpty);
      expect(f.flush().text, isEmpty);
    });

    test('a lone < at chunk end is held back, then released', () {
      final f = InlineThinkStreamFilter();
      final a = f.feed('x <');
      final b = f.feed('3 y');
      expect(a.text + b.text, 'x <3 y');
    });

    test('unterminated think at stream end flushes as reasoning', () {
      final f = InlineThinkStreamFilter();
      final a = f.feed('<think>never closed');
      final flush = f.flush();
      expect(a.text, isEmpty);
      expect(a.reasoning + flush.reasoning, 'never closed');
    });
  });

  group('throwIfEnvelopeError', () {
    test('error field throws with the upstream message', () {
      expect(
        () => throwIfEnvelopeError({'error': {'message': 'insufficient credits'}}),
        throwsA(predicate((e) => e.toString().contains('insufficient credits'))),
      );
    });

    test('base_resp non-zero status throws — an expired key must not read as an empty reply', () {
      expect(
        () => throwIfEnvelopeError({
          'base_resp': {'status_code': 1004, 'status_msg': 'invalid api key'}
        }),
        throwsA(predicate((e) => e.toString().contains('1004'))),
      );
    });

    test('base_resp zero and clean bodies pass', () {
      throwIfEnvelopeError({'base_resp': {'status_code': 0}});
      throwIfEnvelopeError({'choices': []});
    });
  });

  group('reasoning echo-back in the chat payload', () {
    final protocol = OpenAIChatProtocol();

    test('a tool-calling assistant turn replays reasoning under its original field name', () {
      final payload = protocol.buildChatPayloadForTest(
        target('some-model'),
        [
          LLMMessage(role: LLMRole.user, content: 'hi'),
          LLMMessage(
            role: LLMRole.assistant,
            content: '',
            reasoningContent: 'thought hard',
            reasoningFieldName: 'reasoning_content',
            toolCalls: [
              LLMToolCall(id: 'call_1', name: 'f', arguments: {'x': 1}),
            ],
          ),
          LLMMessage(role: LLMRole.tool, content: '{}', toolCallId: 'call_1', toolName: 'f'),
        ],
        isStreaming: false,
      );

      final assistant = (payload['messages'] as List)[1] as Map;
      expect(assistant['reasoning_content'], 'thought hard');
      // The nested tool shape and the nullable-but-present content survive.
      expect(assistant.containsKey('content'), isTrue);
      expect(assistant['content'], isNull);
      expect(assistant['tool_calls'][0]['function']['name'], 'f');
    });

    test('the alternate field name is echoed as received', () {
      final payload = protocol.buildChatPayloadForTest(
        target('some-model'),
        [
          LLMMessage(
            role: LLMRole.assistant,
            content: 'partial',
            reasoningContent: 'r',
            reasoningFieldName: 'reasoning',
            toolCalls: [LLMToolCall(id: 'c', name: 'f', arguments: {})],
          ),
        ],
        isStreaming: false,
      );
      final assistant = (payload['messages'] as List)[0] as Map;
      expect(assistant['reasoning'], 'r');
      expect(assistant.containsKey('reasoning_content'), isFalse);
    });

    test('inline reasoning (no field name) is never echoed', () {
      final payload = protocol.buildChatPayloadForTest(
        target('some-model'),
        [
          LLMMessage(
            role: LLMRole.assistant,
            content: '',
            reasoningContent: 'from <think>',
            reasoningFieldName: null,
            toolCalls: [LLMToolCall(id: 'c', name: 'f', arguments: {})],
          ),
        ],
        isStreaming: false,
      );
      final assistant = (payload['messages'] as List)[0] as Map;
      expect(assistant.containsKey('reasoning_content'), isFalse);
      expect(assistant.containsKey('reasoning'), isFalse);
    });

    test('an assistant turn without tool calls does not echo reasoning', () {
      final payload = protocol.buildChatPayloadForTest(
        target('some-model'),
        [
          LLMMessage(
            role: LLMRole.assistant,
            content: 'plain reply',
            reasoningContent: 'r',
            reasoningFieldName: 'reasoning_content',
          ),
        ],
        isStreaming: false,
      );
      final assistant = (payload['messages'] as List)[0] as Map;
      expect(assistant.containsKey('reasoning_content'), isFalse);
    });
  });

  group('LLMMessage persistence round-trip', () {
    test('reasoning fields survive toJson/fromJson — the echo obligation outlives restarts', () {
      final msg = LLMMessage(
        role: LLMRole.assistant,
        content: 'c',
        reasoningContent: 'deep thought',
        reasoningFieldName: 'reasoning_content',
        toolCalls: [LLMToolCall(id: 'i', name: 'f', arguments: {})],
      );
      final restored = LLMMessage.fromJson(msg.toJson());
      expect(restored.reasoningContent, 'deep thought');
      expect(restored.reasoningFieldName, 'reasoning_content');
    });
  });

  group('ModelDescriptor.acceptsImageInput', () {
    test('deepseek ids are text-only; others keep the historical default', () {
      expect(ModelDescriptor.of('deepseek-chat').acceptsImageInput, isFalse);
      expect(ModelDescriptor.of('deepseek-reasoner').acceptsImageInput, isFalse);
      expect(ModelDescriptor.of('gpt-5-chat').acceptsImageInput, isTrue);
      expect(ModelDescriptor.of('gemini-2.5-flash').acceptsImageInput, isTrue);
    });
  });
}
