import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// The turn after submit_prompt. Once the tool has staged the deliverable,
/// GPT-5.x ends its turn with an empty `stop`; ① fails a reply with nothing
/// in it unless the caller declared that legitimate ([emptyReplyEndsTurnKey]).
/// The agent declares it on exactly the requests that continue after a tool
/// result — never on the one that opens on the user's message, where an
/// empty answer is still a failure the user must see.
void main() {
  usePrivateDataDir('joycai_empty_reply_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  test('only the request after a tool result declares an empty ending', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    final declared = <bool>[];
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      declared.add(options[emptyReplyEndsTurnKey] == true);
      if (declared.length == 1) {
        return LLMResponse(text: '', toolCalls: [
          LLMToolCall(
              id: 'c1', name: 'submit_prompt', arguments: const {'prompt': 'a prompt'}),
        ]);
      }
      // What the wire delivers under the declaration: nothing at all.
      return LLMResponse(text: '', metadata: const {'finish_reason': 'stop'});
    };

    await PromptOptimizerAgent.runTurn(
        session: session, modelIdentifier: 'm', referenceImages: const []);

    expect(declared, [false, true]);
    expect(session.promptVersions, 1);
    expect(session.transcript.any((e) => e.kind == OptimizerEntryKind.error), isFalse,
        reason: 'the empty ending after a delivered prompt is not a failure');
  });

  test('a turn that opens on the user message never declares it', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    Map<String, dynamic>? seen;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      seen = Map.of(options);
      return LLMResponse(text: 'hello');
    };

    await PromptOptimizerAgent.runTurn(
        session: session, modelIdentifier: 'm', referenceImages: const []);

    expect(seen, isNotNull);
    expect(seen!.containsKey(emptyReplyEndsTurnKey), isFalse);
  });
}
