import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/providers/google_payload.dart';

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
}
