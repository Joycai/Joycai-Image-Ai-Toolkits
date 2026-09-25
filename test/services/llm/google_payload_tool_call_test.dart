import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';

void main() {
  group('Google function calling thought signatures', () {
    test('parseGoogleChunks captures thoughtSignature from functionCall part', () {
      final chunk = {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'name': 'list_files',
                    'args': {'dir': '.'},
                  },
                  'thoughtSignature': 'sig-abc123',
                },
                {
                  'functionCall': {
                    'name': 'read_file',
                    'args': {'path': 'a.png'},
                  },
                },
              ],
            },
          },
        ],
      };

      final calls = parseGoogleChunks(
        chunk,
      ).map((c) => c.toolCallPart).whereType<LLMToolCall>().toList();

      expect(calls, hasLength(2));
      expect(calls[0].name, 'list_files');
      expect(calls[0].thoughtSignature, 'sig-abc123');
      expect(calls[1].thoughtSignature, isNull);
    });

    test('prepareGooglePayload echoes thoughtSignature back on functionCall part', () {
      final history = [
        LLMMessage(role: LLMRole.user, content: 'rename my files'),
        LLMMessage(
          role: LLMRole.assistant,
          content: '',
          toolCalls: [
            LLMToolCall(
              id: 'call_list_files_0',
              name: 'list_files',
              arguments: {'dir': '.'},
              thoughtSignature: 'sig-abc123',
            ),
            LLMToolCall(id: 'call_read_file_1', name: 'read_file', arguments: {'path': 'a.png'}),
          ],
        ),
        LLMMessage(
          role: LLMRole.tool,
          content: '{"files": []}',
          toolCallId: 'call_list_files_0',
          toolName: 'list_files',
        ),
      ];

      final payload = prepareGooglePayload(history, null, null);
      final contents = payload['contents'] as List;
      final modelParts = (contents[1] as Map)['parts'] as List;

      expect(modelParts[0]['thoughtSignature'], 'sig-abc123');
      expect((modelParts[0] as Map).containsKey('functionCall'), isTrue);
      // A call that came back without a signature must not send the key at all.
      expect((modelParts[1] as Map).containsKey('thoughtSignature'), isFalse);
    });
  });

  group('thought signatures are model-scoped (reasoning 03 §5)', () {
    List<LLMMessage> history(String? producer) => [
      LLMMessage(role: LLMRole.user, content: 'go'),
      LLMMessage(
        role: LLMRole.assistant,
        content: '',
        rawThinkingModelId: producer,
        toolCalls: [
          LLMToolCall(id: 'g1', name: 'list_files', arguments: const {}, thoughtSignature: 'sig-x'),
        ],
      ),
    ];

    Map signedPart(String? producer, String target) =>
        (((prepareGooglePayload(history(producer), null, null, modelId: target)['contents']
                            as List)[1]
                        as Map)['parts']
                    as List)
                .single
            as Map;

    test('the producing model gets the signature back', () {
      expect(signedPart('gemini-3-pro', 'gemini-3-pro')['thoughtSignature'], 'sig-x');
    });

    test('another model does not', () {
      expect(
        signedPart('gemini-3-pro', 'gemini-2.5-flash').containsKey('thoughtSignature'),
        isFalse,
      );
    });

    test('a turn with no recorded producer still replays it', () {
      expect(signedPart(null, 'gemini-2.5-flash')['thoughtSignature'], 'sig-x');
    });
  });

  group('synthesized call ids (protocol 02 §3.2)', () {
    Map<String, dynamic> callChunk(List<String> names) => {
      'candidates': [
        {
          'content': {
            'parts': [
              for (final n in names)
                {
                  'functionCall': {'name': n, 'args': <String, dynamic>{}},
                },
            ],
          },
        },
      ],
    };

    List<String> idsOf(Iterable<LLMResponseChunk> chunks) =>
        chunks.map((c) => c.toolCallPart?.id).nonNulls.toList();

    test('calls in one chunk get distinct ids', () {
      final ids = idsOf(parseGoogleChunks(callChunk(['a', 'a'])));
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      expect(ids.every((id) => id.startsWith('gtc_')), isTrue);
    });

    test('calls in separate chunks of one stream do not collide', () {
      // ③ streams whole parts per chunk; the counter used to restart at 0
      // on every chunk, so `call_read_0` named two different calls.
      final state = GeminiToolCallIds();
      final first = idsOf(parseGoogleChunks(callChunk(['read']), callIds: state));
      final second = idsOf(parseGoogleChunks(callChunk(['read']), callIds: state));
      expect(first.single, isNot(second.single));
    });

    test('the same call in two turns does not reuse an id', () {
      // History pairs results by id; a second turn's `call_read_0` answered
      // the first turn's call as far as the id map could tell.
      final turn1 = idsOf(parseGoogleChunks(callChunk(['read'])));
      final turn2 = idsOf(parseGoogleChunks(callChunk(['read'])));
      expect(turn1.single, isNot(turn2.single));
    });
  });

  group('history shape (protocol 02 §2.2)', () {
    List<Map> contentsOf(List<LLMMessage> history) =>
        (prepareGooglePayload(history, null, null)['contents'] as List).cast<Map>();

    test('parallel tool results travel in one user content', () {
      final contents = contentsOf([
        LLMMessage(role: LLMRole.user, content: 'do both'),
        LLMMessage(
          role: LLMRole.assistant,
          content: '',
          toolCalls: [
            LLMToolCall(id: 'g1', name: 'a', arguments: const {}),
            LLMToolCall(id: 'g2', name: 'b', arguments: const {}),
          ],
        ),
        LLMMessage(role: LLMRole.tool, content: '{"r":1}', toolCallId: 'g1', toolName: 'a'),
        LLMMessage(role: LLMRole.tool, content: '{"r":2}', toolCallId: 'g2', toolName: 'b'),
      ]);
      expect(contents, hasLength(3));
      final parts = contents.last['parts'] as List;
      expect(contents.last['role'], 'user');
      expect(parts.map((p) => (p as Map)['functionResponse']['name']), ['a', 'b']);
    });

    test('a user turn after the results stays its own content', () {
      // The assistant's `[view_image result]` message follows the results
      // as a separate user turn carrying the picture; it is not a result.
      final contents = contentsOf([
        LLMMessage(role: LLMRole.user, content: 'look'),
        LLMMessage(
          role: LLMRole.assistant,
          content: '',
          toolCalls: [LLMToolCall(id: 'g1', name: 'view_image', arguments: const {})],
        ),
        LLMMessage(role: LLMRole.tool, content: 'ok', toolCallId: 'g1', toolName: 'view_image'),
        LLMMessage(
          role: LLMRole.user,
          content: '[view_image result] Reference image #1 is attached.',
        ),
      ]);
      expect(contents, hasLength(4));
      expect((contents[2]['parts'] as List).single, contains('functionResponse'));
      expect((contents[3]['parts'] as List).single, contains('text'));
    });

    test('an assistant turn with nothing in it is not sent', () {
      final contents = contentsOf([
        LLMMessage(role: LLMRole.user, content: 'hi'),
        LLMMessage(role: LLMRole.assistant, content: ''),
        LLMMessage(role: LLMRole.user, content: 'still there?'),
      ]);
      expect(contents.every((c) => (c['parts'] as List).isNotEmpty), isTrue);
      expect(contents.map((c) => c['role']), ['user', 'user']);
    });

    test('a result missing its tool name takes it from the call it answers', () {
      final contents = contentsOf([
        LLMMessage(role: LLMRole.user, content: 'go'),
        LLMMessage(
          role: LLMRole.assistant,
          content: '',
          toolCalls: [LLMToolCall(id: 'g1', name: 'list_files', arguments: const {})],
        ),
        LLMMessage(role: LLMRole.tool, content: '[]', toolCallId: 'g1'),
      ]);
      final fr = ((contents.last['parts'] as List).single as Map)['functionResponse'] as Map;
      expect(fr['name'], 'list_files');
    });
  });

  group('③ on the streaming surface', () {
    // ③ needed no accumulator: a functionCall arrives whole inside a streamed
    // candidate part, and the parser below is the *same* one the synchronous
    // path uses. Declaring tools on the stream was the only missing piece —
    // and a streamingDeclaresTools that the payload did not back up would
    // answer tool-bearing requests as though no tools existed.
    final tools = [
      LLMTool(
        name: 'read_knowledge_file',
        description: 'Read one rule file.',
        parameters: const {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
        },
      ),
    ];

    test('the payload declares them', () {
      final payload = prepareGooglePayload(
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        null,
        'https://generativelanguage.googleapis.com/v1beta',
        tools: tools,
      );

      final declared = (payload['tools'] as List).first as Map;
      final names = (declared['functionDeclarations'] as List)
          .map((d) => (d as Map)['name'])
          .toList();
      expect(names, ['read_knowledge_file']);
    });

    test('a streamed call arrives whole, with its signature intact', () {
      // thoughtSignature is ③'s entire replay obligation — a tool-calling turn
      // replayed without it is INVALID_ARGUMENT — and the streaming path has
      // to carry it just as the synchronous one does.
      final chunks = geminiChunksFromSseLine(
        'data: {"candidates":[{"content":{"parts":[{"functionCall":'
        '{"name":"read_knowledge_file","args":{"path":"07a.md"}},'
        '"thoughtSignature":"sig-stream"}]}}]}',
      ).toList();

      final call = chunks.map((c) => c.toolCallPart).nonNulls.single;
      expect(call.name, 'read_knowledge_file');
      expect(call.arguments, {'path': '07a.md'});
      expect(call.thoughtSignature, 'sig-stream');
    });

    test('a signature captured from a stream replays verbatim', () {
      // The round trip that matters: stream -> history -> next request.
      final call = geminiChunksFromSseLine(
        'data: {"candidates":[{"content":{"parts":[{"functionCall":'
        '{"name":"read_knowledge_file","args":{"path":"07a.md"}},'
        '"thoughtSignature":"sig-stream"}]}}]}',
      ).map((c) => c.toolCallPart).nonNulls.single;

      final payload = prepareGooglePayload(
        [
          LLMMessage(role: LLMRole.user, content: 'hi'),
          LLMMessage(role: LLMRole.assistant, content: '', toolCalls: [call]),
        ],
        null,
        'https://generativelanguage.googleapis.com/v1beta',
        tools: tools,
      );

      final parts = ((payload['contents'] as List).last as Map)['parts'] as List;
      final fn = parts.firstWhere((p) => (p as Map).containsKey('functionCall'));
      expect((fn as Map)['thoughtSignature'], 'sig-stream');
    });
  });
}
