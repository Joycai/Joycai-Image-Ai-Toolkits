import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// Standard 07 §4.6 rule 3: a tool call is dispatched only when the tool was
/// offered in that request. A model can name any tool it has ever heard of.
void main() {
  usePrivateDataDir('joycai_tool_dispatch_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  test('a tool that was not offered is refused, not executed', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    var requests = 0;
    List<LLMMessage>? followUp;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      if (requests == 1) {
        final offered = tools!.map((t) => t.name).toSet();
        expect(offered, isNot(contains('read_note')));
        expect(offered, isNot(contains('write_knowledge_file')));
        return LLMResponse(
          text: '',
          toolCalls: [
            LLMToolCall(id: 'a', name: 'read_note', arguments: const {'note_id': 1}),
            LLMToolCall(
              id: 'b',
              name: 'write_knowledge_file',
              arguments: const {'path': 'a.md', 'content': 'x'},
            ),
          ],
        );
      }
      followUp = List.of(messages);
      return LLMResponse(text: 'ok');
    };

    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
    );

    final results = [
      for (final m in followUp!)
        if (m.role == LLMRole.tool) m,
    ];
    expect(results.map((m) => m.toolCallId), ['a', 'b'], reason: 'still paired');
    for (final r in results) {
      final decoded = jsonDecode(r.content) as Map;
      expect(decoded['status'], 'error');
      expect(decoded['message'], contains('not offered'), reason: r.toolName);
    }
    expect(session.transcript.where((e) => e.kind == OptimizerEntryKind.kbEdit), isEmpty);
  });

  test('an offered tool still runs', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      if (requests == 1) {
        return LLMResponse(
          text: '',
          toolCalls: [
            LLMToolCall(id: 's', name: 'submit_prompt', arguments: const {'prompt': 'a cat'}),
          ],
        );
      }
      return LLMResponse(text: 'done');
    };

    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
    );
    expect(session.refinedPrompt, 'a cat');
  });
}
