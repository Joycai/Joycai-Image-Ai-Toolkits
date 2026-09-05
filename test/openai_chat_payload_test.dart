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

  group('contentToText', () {
    test('a plain string passes through — the spec shape', () {
      expect(contentToText('hello'), 'hello');
    });

    test('a content array is joined, not downcast into a TypeError', () {
      // Compat layers fronting a Responses/Anthropic backend mirror this
      // shape onto chat/completions. `String text = message['content']` used
      // to throw from inside the parser, surfacing as a request failure with
      // nothing pointing at the cause.
      expect(
        contentToText([
          {'type': 'text', 'text': 'part one '},
          {'type': 'image_url', 'image_url': {'url': 'data:…'}},
          {'type': 'text', 'text': 'part two'},
        ]),
        'part one part two',
      );
    });

    test('absent or unrecognized content reads as empty, never as a throw', () {
      expect(contentToText(null), '');
      expect(contentToText(42), '');
      expect(contentToText([]), '');
      expect(contentToText([{'type': 'image_url'}]), '');
    });
  });

  group('resolveToolCallId', () {
    test('a real id is kept verbatim', () {
      expect(resolveToolCallId('call_abc', 0), 'call_abc');
    });

    test('absent AND empty ids both fall back — an empty one used to survive', () {
      // Two calls in one batch sharing '' would give two tool messages the
      // same tool_call_id, and the next request is rejected.
      expect(resolveToolCallId(null, 0), 'call_0');
      expect(resolveToolCallId('', 1), 'call_1');
      expect(resolveToolCallId('', 0), isNot(resolveToolCallId('', 1)));
    });
  });

  group('sseDataPayload', () {
    test('the spec-optional space after data: is accepted either way', () {
      // `data:{…}` is as conformant as `data: {…}`; only the spaced form was
      // recognized, so a relay using the bare one delivered a reply that
      // parsed as nothing, with no error raised anywhere.
      expect(sseDataPayload('data: {"a":1}'), '{"a":1}');
      expect(sseDataPayload('data:{"a":1}'), '{"a":1}');
    });

    test('only one space is consumed — leading whitespace inside is preserved', () {
      expect(sseDataPayload('data:  {"a":1}'), ' {"a":1}');
    });

    test('terminators, comments and blanks carry no payload', () {
      expect(sseDataPayload('data: [DONE]'), isNull);
      expect(sseDataPayload('data:[DONE]'), isNull);
      expect(sseDataPayload(''), isNull);
      expect(sseDataPayload('   '), isNull);
      expect(sseDataPayload('data:'), isNull);
      expect(sseDataPayload(': keep-alive'), isNull);
    });

    test('a stray CR from \\r\\n framing is stripped', () {
      expect(sseDataPayload('data: {"a":1}\r'), '{"a":1}');
      expect(sseDataPayload('data: [DONE]\r'), isNull);
    });

    test('an unframed JSON line still passes through', () {
      // Some relays stream bare JSON lines with no SSE field name; that
      // tolerance predates this helper and is kept.
      expect(sseDataPayload('{"a":1}'), '{"a":1}');
    });
  });

  group('firstChoice', () {
    test('an empty choices list reads as absent, not as a RangeError', () {
      // The `stream_options.include_usage` tail chunk is exactly this shape.
      // `chunk['choices']?[0]` threw into the stream loop's tolerant catch,
      // so every streamed request silently recorded zero token usage.
      final tail = {
        'id': 'x',
        'choices': [],
        'usage': {'prompt_tokens': 10, 'completion_tokens': 2},
      };
      expect(firstChoice(tail), isNull);
      expect(tail['usage'], isNotNull);
    });

    test('a missing or malformed choices field reads as absent', () {
      expect(firstChoice({'usage': {}}), isNull);
      expect(firstChoice({'choices': 'nope'}), isNull);
      expect(firstChoice({'choices': ['nope']}), isNull);
    });

    test('a real choice is returned as a typed map', () {
      final choice = firstChoice({
        'choices': [
          {'index': 0, 'delta': {'content': 'hi'}, 'finish_reason': null}
        ]
      });
      expect(choice?['delta']['content'], 'hi');
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

  group('reasoning effort (① wire)', () {
    final protocol = OpenAIChatProtocol();

    LLMTarget effortTarget({ReasoningEffort? effort, bool legacy = false}) {
      final config = LLMModelConfig(
        modelId: 'o3-mini',
        channelType: Vendors.openAIRest,
        endpoint: 'https://api.example.com/v1',
        apiKey: 'k',
        enableThinking: legacy,
        reasoningEffort: effort,
      );
      return LLMTarget(
        config: config,
        vendor: Vendors.byId(config.channelType),
        model: ModelDescriptor.of(config.modelId),
      );
    }

    Map<String, dynamic> payloadFor(LLMTarget t) => protocol
        .buildChatPayloadForTest(
            t, [LLMMessage(role: LLMRole.user, content: 'hi')],
            isStreaming: false);

    test('default sends no field at all', () {
      // Minimal common denominator: every proactively sent field is one some
      // relay can 400 on.
      expect(payloadFor(effortTarget()), isNot(contains('reasoning_effort')));
    });

    test('levels translate to the ① spelling, off included', () {
      expect(payloadFor(effortTarget(effort: ReasoningEffort.off))['reasoning_effort'], 'none');
      expect(payloadFor(effortTarget(effort: ReasoningEffort.low))['reasoning_effort'], 'low');
      expect(payloadFor(effortTarget(effort: ReasoningEffort.max))['reasoning_effort'], 'max');
    });

    test('the legacy thinking flag reads as medium', () {
      // Pre-v35 rows (and backups from older builds) carry only the boolean.
      expect(payloadFor(effortTarget(legacy: true))['reasoning_effort'], 'medium');
    });

    test('DeepSeek switches off with the thinking object, not with none', () {
      // DeepSeek's reasoning_effort ladder has no `none`: the value is
      // ignored and the model thinks — and bills — as usual, with nothing in
      // the reply to say so. Its off switch is the top-level object.
      LLMTarget deepseek(ReasoningEffort? effort) {
        final config = LLMModelConfig(
          modelId: 'deepseek-v4-pro',
          channelType: Vendors.deepseek,
          endpoint: 'https://api.deepseek.com',
          apiKey: 'k',
          reasoningEffort: effort,
        );
        return LLMTarget(
          config: config,
          vendor: Vendors.byId(config.channelType),
          model: ModelDescriptor.of(config.modelId),
        );
      }

      final off = payloadFor(deepseek(ReasoningEffort.off));
      expect(off['thinking'], {'type': 'disabled'});
      expect(off.containsKey('reasoning_effort'), isFalse);

      // A level keeps the ladder value DeepSeek does read, and says "on"
      // explicitly in the same object.
      final high = payloadFor(deepseek(ReasoningEffort.high));
      expect(high['thinking'], {'type': 'enabled'});
      expect(high['reasoning_effort'], 'high');

      // Default still sends neither.
      final byDefault = payloadFor(deepseek(null));
      expect(byDefault.containsKey('thinking'), isFalse);
      expect(byDefault.containsKey('reasoning_effort'), isFalse);
    });

    test('every other ① vendor never sees the thinking object', () {
      // It is an unknown field there, and an unknown field is a 400 on the
      // official host.
      for (final id in [Vendors.openAIRest, Vendors.newApiOpenAI, Vendors.minimax, Vendors.dashscope]) {
        final config = LLMModelConfig(
          modelId: 'm',
          channelType: id,
          endpoint: 'https://api.example.com/v1',
          apiKey: 'k',
          reasoningEffort: ReasoningEffort.off,
        );
        final p = payloadFor(LLMTarget(
          config: config,
          vendor: Vendors.byId(id),
          model: ModelDescriptor.of('m'),
        ));
        expect(p.containsKey('thinking'), isFalse, reason: id);
        expect(p['reasoning_effort'], 'none', reason: id);
      }
    });

    test('an explicit level beats the legacy flag', () {
      expect(
          payloadFor(effortTarget(effort: ReasoningEffort.off, legacy: true))[
              'reasoning_effort'],
          'none');
    });
  });

  group('ReasoningEffort.tryParse', () {
    test('round-trips names, degrades unknowns to default', () {
      expect(ReasoningEffort.tryParse('high'), ReasoningEffort.high);
      expect(ReasoningEffort.tryParse(null), isNull);
      // A name from a newer build must not fail the model row.
      expect(ReasoningEffort.tryParse('ultra'), isNull);
    });
  });
}
