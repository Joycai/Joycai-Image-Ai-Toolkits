import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// The working row's character count describes the call streaming *now*. A
/// count left behind by a finished or failed request would show the next step
/// as already half-written, or a stopped turn as still producing output.
void main() {
  usePrivateDataDir('joycai_streaming_progress_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  test('a finished request leaves no count for the next step', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    final seenAtRequest = <int?>[];
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      seenAtRequest.add(session.streamingToolArgumentChars.value);
      // What LLMService reports while a long call streams.
      session.streamingToolArgumentChars.value = 4200;
      if (requests == 1) {
        return LLMResponse(
          text: '',
          toolCalls: [LLMToolCall(id: 'c1', name: 'list_reference_images', arguments: const {})],
        );
      }
      return LLMResponse(text: 'done');
    };

    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
    );

    expect(requests, 2);
    expect(seenAtRequest, [
      null,
      null,
    ], reason: 'the second request must not start from the first one\'s count');
    expect(session.streamingToolArgumentChars.value, isNull);
  });

  test('a failed request clears the count too', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      session.streamingToolArgumentChars.value = 900;
      throw Exception('Upstream rate limit exceeded');
    };

    await expectLater(
      PromptOptimizerAgent.runTurn(
        session: session,
        modelIdentifier: 'm',
        referenceImages: const [],
      ),
      throwsException,
    );

    expect(session.streamingToolArgumentChars.value, isNull);
    expect(session.isRunning, isFalse);
    expect(session.transcript.last.kind, OptimizerEntryKind.error);
  });
}
