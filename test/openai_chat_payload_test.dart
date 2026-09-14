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

  // reasoning 03 §6 rule 1: only a <think> at the very start of the reply
  // (leading whitespace allowed) is chain-of-thought. One quoted mid-body is
  // the author's text — a prompt-writing reply that explains the tag used to
  // have the explanation eaten.
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

    test('leading whitespace before the opening tag is allowed', () {
      final r = stripInlineThink('\n  <think>plan</think>\nbody');
      expect(r.text, 'body');
      expect(r.reasoning, 'plan');
    });

    test('a <think> quoted in the body is the author\'s text', () {
      const reply = 'Wrap the plan in <think>…</think> tags, then answer.';
      final r = stripInlineThink(reply);
      expect(r.text, reply);
      expect(r.reasoning, isNull);
    });

    test('only the leading span is reasoning; a later one stays text', () {
      final r = stripInlineThink('<think>a</think>one<think>b</think>two');
      expect(r.text, 'one<think>b</think>two');
      expect(r.reasoning, 'a');
    });

    test('an unterminated leading span swallows the rest as reasoning', () {
      final r = stripInlineThink('<think>and I was cut off');
      expect(r.text, isEmpty);
      expect(r.reasoning, 'and I was cut off');
    });

    test('an unterminated tag mid-body is not reasoning', () {
      final r = stripInlineThink('answer so far<think>and more');
      expect(r.text, 'answer so far<think>and more');
      expect(r.reasoning, isNull);
    });
  });

  group('InlineThinkStreamFilter', () {
    ({String text, String reasoning}) feedAll(List<String> deltas) {
      final f = InlineThinkStreamFilter();
      final text = StringBuffer();
      final reasoning = StringBuffer();
      for (final d in deltas) {
        final out = f.feed(d);
        text.write(out.text);
        reasoning.write(out.reasoning);
      }
      final tail = f.flush();
      text.write(tail.text);
      reasoning.write(tail.reasoning);
      return (text: text.toString(), reasoning: reasoning.toString());
    }

    test('a tag split across chunks is reassembled — <thi + nk> is normal', () {
      final out = feedAll(['<thi', 'nk>secret</th', 'ink>\n\nworld']);
      expect(out.text, 'world');
      expect(out.reasoning, 'secret');
    });

    test('leading whitespace is held until the tag decides', () {
      final out = feedAll(['\n ', ' <think>x</think>', 'y']);
      expect(out.text, 'y');
      expect(out.reasoning, 'x');
    });

    test('plain text streams through without buffering distortion', () {
      final f = InlineThinkStreamFilter();
      final out = f.feed('no tags here');
      expect(out.text, 'no tags here');
      expect(out.reasoning, isEmpty);
      expect(f.flush().text, isEmpty);
    });

    test('a lone < at the start is held back, then released', () {
      final f = InlineThinkStreamFilter();
      final a = f.feed('<');
      expect(a.text, isEmpty);
      final b = f.feed('3 y');
      expect(a.text + b.text, '<3 y');
    });

    test('once the body has started, a tag in it is text', () {
      final out = feedAll(['hello ', '<thi', 'nk>quoted</think> tags']);
      expect(out.text, 'hello <think>quoted</think> tags');
      expect(out.reasoning, isEmpty);
    });

    test('unterminated think at stream end flushes as reasoning', () {
      final f = InlineThinkStreamFilter();
      final a = f.feed('<think>never closed');
      final flush = f.flush();
      expect(a.text, isEmpty);
      expect(a.reasoning + flush.reasoning, 'never closed');
    });

    test('a stream of whitespace alone is still delivered as text', () {
      expect(feedAll(['  ', '\n']).text, '  \n');
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

      final assistant = (payload['messages'] as List)
          .lastWhere((m) => (m as Map)['role'] == 'assistant') as Map;
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
      final assistant = (payload['messages'] as List)
          .lastWhere((m) => (m as Map)['role'] == 'assistant') as Map;
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
      final assistant = (payload['messages'] as List)
          .lastWhere((m) => (m as Map)['role'] == 'assistant') as Map;
      expect(assistant.containsKey('reasoning_content'), isFalse);
      expect(assistant.containsKey('reasoning'), isFalse);
    });

    // reasoning 03 §5.2, pitfalls 11 §A3: a reasoning field belongs to the
    // model that wrote it. Sent to another model, official OpenAI 400s the
    // unknown field and a relay bills it as input.
    group('model scoping', () {
      Map<String, dynamic>? assistantOf(Map<String, dynamic> payload) =>
          (payload['messages'] as List)
              .cast<Map<String, dynamic>>()
              .where((m) => m['role'] == 'assistant')
              .firstOrNull;

      LLMMessage toolTurn(String? producer) => LLMMessage(
            role: LLMRole.assistant,
            content: '',
            reasoningContent: 'deepseek thought',
            reasoningFieldName: 'reasoning_content',
            rawThinkingModelId: producer,
            toolCalls: [LLMToolCall(id: 'c', name: 'f', arguments: {})],
          );

      test('the producing model gets its reasoning back', () {
        final payload = protocol.buildChatPayloadForTest(
          target('deepseek-v4-pro'),
          [toolTurn('deepseek-v4-pro')],
          isStreaming: false,
        );
        expect(assistantOf(payload)!['reasoning_content'], 'deepseek thought');
      });

      test('another model does not', () {
        final payload = protocol.buildChatPayloadForTest(
          target('gpt-5-chat'),
          [toolTurn('deepseek-v4-pro')],
          isStreaming: false,
        );
        expect(assistantOf(payload)!.containsKey('reasoning_content'), isFalse);
      });

      test('a legacy turn with no recorded producer is still echoed', () {
        // Sessions persisted before the producer was recorded must keep
        // working — DeepSeek 400s a tool turn replayed without its reasoning.
        final payload = protocol.buildChatPayloadForTest(
          target('gpt-5-chat'),
          [toolTurn(null)],
          isStreaming: false,
        );
        expect(assistantOf(payload)!['reasoning_content'], 'deepseek thought');
      });
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
      final assistant = (payload['messages'] as List)
          .lastWhere((m) => (m as Map)['role'] == 'assistant') as Map;
      expect(assistant.containsKey('reasoning_content'), isFalse);
    });
  });

  group('a system message is always present (layering 01 §9.2)', () {
    // New API relays inject a 4–9 K-token Codex system prompt into any chat
    // request that carries none — silently, on every request.
    final protocol = OpenAIChatProtocol();

    List<Map> messagesOf(String modelId, List<LLMMessage> history) =>
        (protocol.buildChatPayloadForTest(target(modelId), history,
                isStreaming: false)['messages'] as List)
            .cast<Map>();

    test('a conversation without one gets the neutral line first', () {
      final messages = messagesOf(
          'gpt-5-chat', [LLMMessage(role: LLMRole.user, content: 'hi')]);
      expect(messages.first,
          {'role': 'system', 'content': openaiDefaultSystemPrompt});
      expect(messages.last['content'], 'hi');
    });

    test('the caller\'s own system prompt is not doubled', () {
      final messages = messagesOf('gpt-5-chat', [
        LLMMessage(role: LLMRole.system, content: 'be terse'),
        LLMMessage(role: LLMRole.user, content: 'hi'),
      ]);
      expect(messages.where((m) => m['role'] == 'system'), hasLength(1));
      expect(messages.first['content'], 'be terse');
    });

    test('an image generator on the chat route is left alone', () {
      // The relay turns that call into an images request.
      final messages = messagesOf('gemini-2.5-flash-image',
          [LLMMessage(role: LLMRole.user, content: 'a red apple')]);
      expect(messages.any((m) => m['role'] == 'system'), isFalse);
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
    test('text-only deepseek ids opt out; others keep the historical default', () {
      expect(ModelDescriptor.of('deepseek-chat').acceptsImageInput, isFalse);
      expect(ModelDescriptor.of('deepseek-reasoner').acceptsImageInput, isFalse);
      expect(ModelDescriptor.of('deepseek-v4-pro').acceptsImageInput, isFalse);
      expect(ModelDescriptor.of('deepseek-ai/DeepSeek-V3').acceptsImageInput,
          isFalse);
      expect(ModelDescriptor.of('gpt-5-chat').acceptsImageInput, isTrue);
      expect(ModelDescriptor.of('gemini-2.5-flash').acceptsImageInput, isTrue);
    });

    test('V4.1-Flash and the VL weights see images', () {
      expect(ModelDescriptor.of('deepseek-flash').acceptsImageInput, isTrue);
      // Legacy names, still callable and now served by V4.1-Flash.
      expect(ModelDescriptor.of('deepseek-v4-flash').acceptsImageInput, isTrue);
      expect(
          ModelDescriptor.of('deepseek-v4-flash-vision-exp').acceptsImageInput,
          isTrue);
      expect(
          ModelDescriptor.of('deepseek-ai/deepseek-vl2').acceptsImageInput,
          isTrue);
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
      for (final id in [Vendors.openAIRest, Vendors.newApiOpenAI, Vendors.minimax]) {
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
        expect(p.containsKey('enable_thinking'), isFalse, reason: id);
        expect(p['reasoning_effort'], 'none', reason: id);
      }
    });

    group("DashScope's compatible face declares the enable_thinking switch", () {
      // 03 §3 / pitfalls 11 §A9: Qwen3-Max/Plus think only when told, and
      // reasoning_effort does not tell them. The declared switch is sent
      // *instead of* reasoning_effort, on both Bailian vendors' ① face.
      LLMTarget bailian(String channelType, ReasoningEffort? effort) {
        final config = LLMModelConfig(
          modelId: 'qwen3-max',
          channelType: channelType,
          endpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          apiKey: 'k',
          reasoningEffort: effort,
        );
        return LLMTarget(
          config: config,
          vendor: Vendors.byId(channelType),
          model: ModelDescriptor.of(config.modelId),
        );
      }

      for (final vendor in [Vendors.dashscope, Vendors.dashscopeNative]) {
        test('$vendor: off, on, and default', () {
          final off = payloadFor(bailian(vendor, ReasoningEffort.off));
          expect(off['enable_thinking'], isFalse);
          expect(off.containsKey('reasoning_effort'), isFalse);
          expect(off.containsKey('thinking'), isFalse);

          for (final level in [
            ReasoningEffort.low,
            ReasoningEffort.medium,
            ReasoningEffort.high,
            ReasoningEffort.max,
          ]) {
            final on = payloadFor(bailian(vendor, level));
            expect(on['enable_thinking'], isTrue, reason: level.name);
            expect(on.containsKey('reasoning_effort'), isFalse,
                reason: level.name);
          }

          final byDefault = payloadFor(bailian(vendor, null));
          expect(byDefault.containsKey('enable_thinking'), isFalse);
          expect(byDefault.containsKey('reasoning_effort'), isFalse);
        });
      }

      test('tools stay on auto while thinking is on', () {
        // Qwen accepts only auto|none as tool_choice with thinking enabled
        // (pitfalls 11 §A13, tools 04 §4). This wire never forces a tool, so
        // the downgrade the rule asks for is already the only behaviour.
        final p = protocol.buildChatPayloadForTest(
          bailian(Vendors.dashscope, ReasoningEffort.high),
          [LLMMessage(role: LLMRole.user, content: 'hi')],
          isStreaming: false,
          tools: [
            LLMTool(
                name: 'f',
                description: 'd',
                parameters: const {'type': 'object'}),
          ],
        );
        expect(p['enable_thinking'], isTrue);
        expect(p['tool_choice'], 'auto');
      });
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
