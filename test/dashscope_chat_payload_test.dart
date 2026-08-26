import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins DashScope's **native** chat wire (protocol C2 in
/// `docs/api/qianwen-bailian.md`). Every rule here is one that fails silently
/// rather than loudly when it is wrong: a body section in the wrong place is
/// ignored, `result_format` left at its default answers with no `choices` at
/// all, and an image sent to the text endpoint is dropped without a word.
void main() {
  LLMTarget target(String modelId,
          {String channelType = Vendors.dashscopeNative,
          String endpoint = 'https://dashscope.aliyuncs.com/api/v1',
          ReasoningEffort? effort}) =>
      LLMTarget(
        config: LLMModelConfig(
          modelId: modelId,
          channelType: channelType,
          endpoint: endpoint,
          apiKey: 'k',
          reasoningEffort: effort,
        ),
        vendor: Vendors.byId(channelType),
        model: ModelDescriptor.of(modelId),
      );

  LLMMessage user(String text) =>
      LLMMessage(role: LLMRole.user, content: text);

  group('endpoint selection', () {
    test('text models take the text-generation path', () {
      expect(
        dashscopeChatUrl('https://dashscope.aliyuncs.com/api/v1', false),
        'https://dashscope.aliyuncs.com/api/v1'
            '/services/aigc/text-generation/generation',
      );
    });

    test('multimodal models take the multimodal path', () {
      expect(
        dashscopeChatUrl('https://dashscope.aliyuncs.com/api/v1', true),
        'https://dashscope.aliyuncs.com/api/v1'
            '/services/aigc/multimodal-generation/generation',
      );
    });

    test('the base is derived, so a compatible-mode channel reaches it too',
        () {
      expect(
        dashscopeChatUrl(
            'https://dashscope.aliyuncs.com/compatible-mode/v1', false),
        'https://dashscope.aliyuncs.com/api/v1'
            '/services/aigc/text-generation/generation',
      );
    });

    test('VL / omni / audio ids declare themselves multimodal', () {
      for (final id in ['qwen3-vl-plus', 'qwen-vl', 'qwen-omni-turbo',
                        'qwen-audio-turbo']) {
        expect(dashscopeChatIsMultimodal(target(id), [user('hi')]), isTrue,
            reason: id);
      }
      expect(dashscopeChatIsMultimodal(target('qwen-max'), [user('hi')]),
          isFalse);
    });

    test('an attachment forces the multimodal path on any model', () {
      // The text endpoint accepts the request and drops the image, so the
      // model answers as though it never saw one — no error to notice.
      final withImage = LLMMessage(
        role: LLMRole.user,
        content: 'what is this',
        attachments: [
          LLMAttachment.fromBytes(Uint8List.fromList([1, 2, 3]), 'image/png'),
        ],
      );
      expect(dashscopeChatIsMultimodal(target('qwen-max'), [withImage]),
          isTrue);
    });
  });

  group('request body', () {
    test('is three-section, with the conversation under input', () {
      final payload = buildDashScopeChatPayload(
        target('qwen-max'),
        [user('hello')],
        multimodal: false,
        isStreaming: false,
      );
      expect(payload.keys, containsAll(['model', 'input', 'parameters']));
      expect(payload['model'], 'qwen-max');
      expect(payload['input'], {
        'messages': [
          {'role': 'user', 'content': 'hello'}
        ]
      });
      // Never omitted: the default ("text") answers with a bare string and
      // no choices, which reads as an empty reply rather than a wrong request.
      expect((payload['parameters'] as Map)['result_format'], 'message');
    });

    test('streaming asks for deltas; non-streaming does not', () {
      Map params(bool streaming) => buildDashScopeChatPayload(
            target('qwen-max'),
            [user('hi')],
            multimodal: false,
            isStreaming: streaming,
          )['parameters'] as Map<String, dynamic>;

      expect(params(true)['incremental_output'], isTrue);
      expect(params(false).containsKey('incremental_output'), isFalse);
    });

    test('tools go under parameters, in the ①-shaped function form', () {
      final payload = buildDashScopeChatPayload(
        target('qwen-max'),
        [user('hi')],
        tools: [
          LLMTool(
            name: 'read_file',
            description: 'read one file',
            parameters: {'type': 'object', 'properties': {}},
          )
        ],
        multimodal: false,
        isStreaming: false,
      );
      final params = payload['parameters'] as Map<String, dynamic>;
      expect(params['tools'], [
        {
          'type': 'function',
          'function': {
            'name': 'read_file',
            'description': 'read one file',
            'parameters': {'type': 'object', 'properties': {}},
          },
        }
      ]);
      expect(params['tool_choice'], 'auto');
      // The conversation stays where it belongs — a `tools` key placed
      // beside `input` is accepted and ignored.
      expect((payload['input'] as Map).containsKey('tools'), isFalse);
    });

    test('a tool result carries both pairing keys', () {
      final payload = buildDashScopeChatPayload(
        target('qwen-max'),
        [
          LLMMessage(
            role: LLMRole.tool,
            content: '42',
            toolCallId: 'call_1',
            toolName: 'read_file',
          )
        ],
        multimodal: false,
        isStreaming: false,
      );
      expect((payload['input'] as Map)['messages'], [
        {
          'role': 'tool',
          'content': '42',
          'tool_call_id': 'call_1',
          'name': 'read_file',
        }
      ]);
    });

    test('an assistant tool-call turn replays its reasoning field', () {
      final payload = buildDashScopeChatPayload(
        target('qwen-max'),
        [
          LLMMessage(
            role: LLMRole.assistant,
            content: '',
            reasoningContent: 'thought',
            reasoningFieldName: 'reasoning_content',
            toolCalls: [
              LLMToolCall(
                  id: 'call_1', name: 'read_file', arguments: {'path': 'a'})
            ],
          )
        ],
        multimodal: false,
        isStreaming: false,
      );
      final message = ((payload['input'] as Map)['messages'] as List).first
          as Map<String, dynamic>;
      expect(message['reasoning_content'], 'thought');
      expect(message['content'], '');
      expect(message['tool_calls'], [
        {
          'id': 'call_1',
          'type': 'function',
          'function': {
            'name': 'read_file',
            'arguments': '{"path":"a"}',
          },
        }
      ]);
    });

    test('multimodal content is always a list, images first', () {
      final payload = buildDashScopeChatPayload(
        target('qwen3-vl-plus'),
        [
          LLMMessage(
            role: LLMRole.user,
            content: 'describe',
            attachments: [
              LLMAttachment.fromBytes(
                  Uint8List.fromList([1, 2, 3]), 'image/png'),
            ],
          ),
          user('and again'),
        ],
        multimodal: true,
        isStreaming: false,
      );
      final messages = (payload['input'] as Map)['messages'] as List;
      expect(messages.first['content'], [
        {'image': 'data:image/png;base64,${base64Encode([1, 2, 3])}'},
        {'text': 'describe'},
      ]);
      // A text-only turn on this endpoint is still a list — a bare string is
      // rejected there.
      expect(messages.last['content'], [
        {'text': 'and again'}
      ]);
    });
  });

  group('thinking', () {
    test('nothing is sent until the user picks a level', () {
      expect(dashscopeThinkingRequest(null), isNull);
      final params = buildDashScopeChatPayload(
        target('qwen-max'),
        [user('hi')],
        multimodal: false,
        isStreaming: false,
      )['parameters'] as Map<String, dynamic>;
      expect(params.containsKey('enable_thinking'), isFalse);
    });

    test('every level above off is the same on/off switch here', () {
      expect(dashscopeThinkingRequest(ReasoningEffort.off), isFalse);
      for (final effort in [
        ReasoningEffort.low,
        ReasoningEffort.medium,
        ReasoningEffort.high,
        ReasoningEffort.max,
      ]) {
        expect(dashscopeThinkingRequest(effort), isTrue, reason: effort.name);
      }
    });

    test('the level reaches the body', () {
      final params = buildDashScopeChatPayload(
        target('qwen-max', effort: ReasoningEffort.high),
        [user('hi')],
        multimodal: false,
        isStreaming: false,
      )['parameters'] as Map<String, dynamic>;
      expect(params['enable_thinking'], isTrue);
    });
  });

  group('stream frames', () {
    test('incremental frames pass through as their own deltas', () {
      final channel = DashScopeStreamChannel();
      expect(channel.feed('Hello'), 'Hello');
      expect(channel.feed(' world'), ' world');
      expect(channel.feed('!'), '!');
    });

    test('cumulative frames are trimmed to the tail', () {
      // What arrives when `incremental_output` is refused, or an
      // intermediary re-assembles frames. Appended verbatim it would replay
      // the whole answer on every frame.
      final channel = DashScopeStreamChannel();
      expect(channel.feed('Hello'), 'Hello');
      expect(channel.feed('Hello world'), ' world');
      expect(channel.feed('Hello world!'), '!');
    });

    test('the ambiguity closes as soon as the answer is longer than a frame',
        () {
      // Two frames cannot be told apart when the accumulation *is* the
      // previous frame: "a" then "ab" reads as cumulative either way, and
      // costs one character if it was really a delta. That window is one
      // frame wide — once anything else has been emitted, a delta no longer
      // has the accumulation as its prefix and is passed through whole.
      final ambiguous = DashScopeStreamChannel();
      expect(ambiguous.feed('a'), 'a');
      expect(ambiguous.feed('ab'), 'b');

      final settled = DashScopeStreamChannel();
      expect(settled.feed('x'), 'x');
      expect(settled.feed('a'), 'a');
      expect(settled.feed('ab'), 'ab');
    });
  });

  group('response parsing', () {
    Map<String, dynamic> reply(Map<String, dynamic> message,
            {String finish = 'stop'}) =>
        {
          'output': {
            'choices': [
              {'finish_reason': finish, 'message': message}
            ]
          },
          'usage': {
            'input_tokens': 11,
            'output_tokens': 22,
            'total_tokens': 33
          },
          'request_id': 'req-1',
        };

    test('reads the message out from under output', () {
      final message = dashscopeChatMessage(reply({
        'role': 'assistant',
        'content': 'hi',
        'reasoning_content': 'thought',
      }));
      expect(message?['content'], 'hi');
      expect(message?['reasoning_content'], 'thought');
    });

    test('a body with no choices answers null rather than an empty reply', () {
      expect(dashscopeChatMessage({'output': {}}), isNull);
      expect(dashscopeChatMessage({'output': {'choices': []}}), isNull);
      expect(dashscopeChatMessage({'output': {'text': 'bare'}}), isNull);
    });

    test('"null" as a string means "still going", not a finish reason', () {
      expect(dashscopeFinishReason(reply({'content': ''}, finish: 'null')),
          isNull);
      expect(dashscopeFinishReason(reply({'content': ''})), 'stop');
    });

    test('the text-shaped finish reason on output itself is read too', () {
      expect(
        dashscopeFinishReason({
          'output': {'text': 'hi', 'finish_reason': 'length'}
        }),
        'length',
      );
    });

    test('usage is published under the names the usage recorder reads', () {
      final metadata = dashscopeChatMetadata(reply({'content': 'hi'}));
      // `LLMService._recordUsage` falls back to input_tokens/output_tokens —
      // DashScope's own spelling — so they are passed through, not renamed.
      expect(metadata['input_tokens'], 11);
      expect(metadata['output_tokens'], 22);
      expect(metadata['finish_reason'], 'stop');
      expect(metadata['request_id'], 'req-1');
    });

    test('tool calls come back with decoded arguments and stable ids', () {
      final calls = dashscopeToolCalls({
        'tool_calls': [
          {
            'id': 'call_a',
            'type': 'function',
            'function': {'name': 'read_file', 'arguments': '{"path":"a"}'},
          },
          {
            // No id: two calls in one batch must not share an empty one.
            'function': {'name': 'read_file', 'arguments': '{"path":"b"}'},
          },
        ]
      }, null);
      expect(calls.map((c) => c.id), ['call_a', 'call_1']);
      expect(calls.map((c) => c.arguments), [
        {'path': 'a'},
        {'path': 'b'}
      ]);
    });

    test('malformed arguments degrade to empty, never throw', () {
      final calls = dashscopeToolCalls({
        'tool_calls': [
          {
            'function': {'name': 'x', 'arguments': 'not json'}
          }
        ]
      }, null);
      expect(calls.single.arguments, isEmpty);
    });
  });
}
