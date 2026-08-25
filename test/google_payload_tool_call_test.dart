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

      final calls = parseGoogleChunks(chunk)
          .map((c) => c.toolCallPart)
          .whereType<LLMToolCall>()
          .toList();

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
            LLMToolCall(
              id: 'call_read_file_1',
              name: 'read_file',
              arguments: {'path': 'a.png'},
            ),
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
            'path': {'type': 'string'}
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
