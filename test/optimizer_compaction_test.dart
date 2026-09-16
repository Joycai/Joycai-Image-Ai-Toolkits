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

  group('the latest delivery is carried by the app, not re-typed by the model', () {
    const promptText = 'THE PROMPT: a low-angle shot of a rain-washed stone bridge';

    /// Eight finished turns; the one delivery sits in [inTurn] as a
    /// submit_prompt call with its result. Turn 8 is always kept by the
    /// two-turn floor; turn 2 is always folded.
    PromptOptimizerSession sessionWithDelivery({required int inTurn}) {
      final session = PromptOptimizerSession();
      for (var i = 1; i <= 8; i++) {
        session.addUserTurn('turn $i');
        if (i == inTurn) {
          session.history.add(LLMMessage(role: LLMRole.assistant, content: '', toolCalls: [
            LLMToolCall(id: 'c$i', name: 'submit_prompt', arguments: {'prompt': promptText, 'note': 'first cut'}),
          ]));
          session.history.add(LLMMessage(
              role: LLMRole.tool, content: '{"status":"ok"}', toolCallId: 'c$i', toolName: 'submit_prompt'));
          session.promptVersions = 1;
        }
        session.history.add(LLMMessage(role: LLMRole.assistant, content: 'reply $i ${'x' * 600}'));
      }
      session.addUserTurn('pending question');
      return session;
    }

    test('a folded delivery is appended to the summary verbatim, and its text never reaches the summarizer',
        () async {
      final session = sessionWithDelivery(inTurn: 2);
      String? summaryInput;
      String? summaryInstruction;
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
        if (isSummaryRequest(messages)) {
          summaryInstruction = messages.first.content;
          summaryInput = messages.last.content;
          return LLMResponse(text: 'the gist');
        }
        return LLMResponse(text: 'answer');
      };

      await PromptOptimizerAgent.runTurn(
          session: session, modelIdentifier: 'm', referenceImages: const [], contextWindow: 2000);

      expect(summaryInput, isNotNull);
      expect(summaryInput, isNot(contains(promptText)));
      expect(summaryInput, contains('text omitted'));
      expect(summaryInput, contains('first cut'), reason: 'the note is what distinguished the version');
      expect(summaryInstruction, isNot(contains('in full')));

      final summary = session.history.first.content;
      expect(summary, startsWith(PromptOptimizerAgent.summaryMarker));
      expect(summary, contains('the gist'));
      expect(summary, contains('${PromptOptimizerAgent.latestPromptMarker} v1\n$promptText'));
      expect(summary, endsWith(promptText));
    });

    test('a delivery still in the kept tail is not duplicated into the summary', () async {
      final session = sessionWithDelivery(inTurn: 8);
      final delivery = session.history.firstWhere((m) => m.toolCalls.isNotEmpty);
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async =>
          LLMResponse(text: isSummaryRequest(messages) ? 'the gist' : 'answer');

      await PromptOptimizerAgent.runTurn(
          session: session, modelIdentifier: 'm', referenceImages: const [], contextWindow: 2000);

      expect(session.history.first.content, startsWith(PromptOptimizerAgent.summaryMarker));
      expect(session.history.first.content, isNot(contains(PromptOptimizerAgent.latestPromptMarker)));
      expect(session.history.any((m) => identical(m, delivery)), isTrue);
    });

    test('an earlier summary\'s appended prompt is not fed back into the next summary', () async {
      final session = sessionWithDelivery(inTurn: 2);
      final inputs = <String>[];
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
        if (isSummaryRequest(messages)) {
          inputs.add(messages.last.content);
          return LLMResponse(text: 'the gist');
        }
        return LLMResponse(text: 'answer ${'y' * 600}');
      };

      await PromptOptimizerAgent.runTurn(
          session: session, modelIdentifier: 'm', referenceImages: const [], contextWindow: 2000);
      for (var i = 0; i < 6; i++) {
        session.addUserTurn('more $i');
        await PromptOptimizerAgent.runTurn(
            session: session, modelIdentifier: 'm', referenceImages: const [], contextWindow: 2000);
      }

      expect(inputs.length, greaterThan(1));
      for (final input in inputs) {
        expect(input, isNot(contains(promptText)));
      }
      // Carried forward across the re-compactions, exactly once.
      expect(promptText.allMatches(session.history.first.content).length, 1);
    });
  });
}
