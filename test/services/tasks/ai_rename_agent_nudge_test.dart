import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/ai_rename_agent.dart';

/// A batch whose model answers in plain text without ever calling a tool used
/// to count as done: nothing renamed, no error. It now gets one nudge, then
/// fails loudly.
void main() {
  final files = [
    {'original_name': 'a.png', 'path': '/tmp/rename_test/a.png', 'category': 'image'},
  ];

  test('a text-only batch gets one nudge, then fails loudly', () async {
    var requests = 0;
    await expectLater(
      AiRenameAgent.collectProposals(
        modelIdentifier: 'm',
        filesData: files,
        request: (messages, tools) async {
          requests++;
          return LLMResponse(text: 'I would rename it to sunset.png.');
        },
      ),
      throwsA(isA<Exception>()),
    );
    expect(requests, 2, reason: 'exactly one nudge before giving up');
  });

  test('a nudge that works lets the batch continue normally', () async {
    final seen = <List<LLMMessage>>[];
    final proposals = await AiRenameAgent.collectProposals(
      modelIdentifier: 'm',
      filesData: files,
      request: (messages, tools) async {
        seen.add(messages);
        switch (seen.length) {
          case 1:
            return LLMResponse(text: 'Sure, happy to help.');
          case 2:
            return LLMResponse(
              text: '',
              toolCalls: [
                LLMToolCall(
                  id: 'r1',
                  name: 'rename_file',
                  arguments: const {'id': 1, 'new_name': 'b.png'},
                ),
              ],
            );
          default:
            return LLMResponse(text: 'Done.');
        }
      },
    );
    expect(seen.length, 3);
    expect(
      seen[1].last.role,
      LLMRole.user,
      reason: 'the nudge is a user message after the text-only reply',
    );
    expect(seen[1].length, greaterThan(seen[0].length));
    expect(proposals.single.newName, 'b.png');
  });

  test('a text reply after tools were used still ends the batch without a nudge', () async {
    var requests = 0;
    final proposals = await AiRenameAgent.collectProposals(
      modelIdentifier: 'm',
      filesData: files,
      request: (messages, tools) async {
        requests++;
        if (requests == 1) {
          return LLMResponse(
            text: '',
            toolCalls: [LLMToolCall(id: 'l1', name: 'list_files', arguments: const {})],
          );
        }
        return LLMResponse(text: 'Nothing needs renaming.');
      },
    );
    expect(requests, 2);
    expect(proposals, isEmpty);
  });
}
