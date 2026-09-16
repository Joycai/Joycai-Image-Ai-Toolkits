import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// Layer-2 compaction, driven through runTurn with the request replaced.
void main() {
  usePrivateDataDir('joycai_compaction_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  bool isSummaryRequest(List<LLMMessage> messages) =>
      messages.first.role == LLMRole.system &&
      messages.first.content.startsWith('You compress');

  /// Eight finished turns of bulky assistant text, then a pending question —
  /// far past the budget of a tiny window.
  PromptOptimizerSession overBudgetSession() {
    final session = PromptOptimizerSession();
    for (var i = 1; i <= 8; i++) {
      session.addUserTurn('turn $i');
      session.history.add(LLMMessage(role: LLMRole.assistant, content: 'reply $i ${'x' * 600}'));
    }
    session.addUserTurn('pending question');
    return session;
  }

  group('a failed compaction leaves the history untouched (standard 10 §3.4)', () {
    for (final failure in ['throws', 'returns an empty summary']) {
      test('when the summary request $failure', () async {
        final session = overBudgetSession();
        final before = List.of(session.history);
        var summaryRequests = 0;
        PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
          if (isSummaryRequest(messages)) {
            summaryRequests++;
            if (failure == 'throws') throw Exception('network blip');
            return LLMResponse(text: '   ');
          }
          return LLMResponse(text: 'answer');
        };

        await PromptOptimizerAgent.runTurn(
          session: session,
          modelIdentifier: 'm',
          referenceImages: const [],
          contextWindow: 2000,
        );

        expect(summaryRequests, 1, reason: 'the budget was exceeded, so compaction was attempted');
        expect(session.history.length, before.length + 1, reason: 'only the answer was appended');
        for (var i = 0; i < before.length; i++) {
          expect(identical(session.history[i], before[i]), isTrue, reason: 'message $i was rewritten');
        }
        expect(
          session.history.any((m) => m.content.startsWith(PromptOptimizerAgent.summaryMarker)),
          isFalse,
        );
        expect(
          session.transcript.any((e) => e.text == PromptOptimizerAgent.compactedNoticeToken),
          isFalse,
        );
      });
    }

    test('the next turn tries again', () async {
      final session = overBudgetSession();
      var summaryRequests = 0;
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
        if (isSummaryRequest(messages)) {
          summaryRequests++;
          if (summaryRequests == 1) throw Exception('network blip');
          return LLMResponse(text: 'the gist of turns 1-3');
        }
        return LLMResponse(text: 'answer');
      };

      await PromptOptimizerAgent.runTurn(
          session: session, modelIdentifier: 'm', referenceImages: const [], contextWindow: 2000);
      session.addUserTurn('another question');
      await PromptOptimizerAgent.runTurn(
          session: session, modelIdentifier: 'm', referenceImages: const [], contextWindow: 2000);

      expect(summaryRequests, 2);
      expect(session.history.first.content, startsWith(PromptOptimizerAgent.summaryMarker));
    });
  });
}
