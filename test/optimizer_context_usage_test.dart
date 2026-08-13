import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant_context_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/context_budget.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// What the context readout claims, measured the same way the request is.
///
/// The number on screen and the number the turn is budgeted with come from the
/// same `occupiedChars`, so the failure this pins is a readout that quietly
/// diverges from what actually goes on the wire: counting the raw history
/// instead of the trimmed one, counting the system prompt twice, or presenting
/// the default window assumption as if the user had configured it.
void main() {
  PromptOptimizerSession sessionWith({
    int systemPromptChars = 0,
    int toolSchemaChars = 0,
    List<LLMMessage> history = const [],
  }) {
    final session = PromptOptimizerSession();
    if (systemPromptChars > 0 || toolSchemaChars > 0) {
      session.recordRequestBasis(
        systemPromptChars: systemPromptChars,
        toolSchemaChars: toolSchemaChars,
      );
    }
    session.history.addAll(history);
    return session;
  }

  group('measureContext', () {
    test('a session that has never run reports nothing, not an empty window', () {
      // Zero for the system prompt would be a lie the first turn corrects a
      // second later — it has simply not been built yet.
      final usage = PromptOptimizerAgent.measureContext(
        sessionWith(),
        contextWindowTokens: 131072,
      );
      expect(usage.isUnknown, isTrue);
      expect(usage.basis, ContextWindowBasis.none);
    });

    test('splits the request into system prompt, tools and history', () {
      final usage = PromptOptimizerAgent.measureContext(
        sessionWith(
          systemPromptChars: 4000,
          toolSchemaChars: 1200,
          history: [LLMMessage(role: LLMRole.user, content: 'x' * 300)],
        ),
        contextWindowTokens: 131072,
      );

      expect(usage.slices[ContextUsageSlice.systemPrompt], 4000);
      expect(usage.slices[ContextUsageSlice.tools], 1200);
      // The history slice is the history alone: occupiedChars folds the system
      // prompt in, and passing it here would count it in two slices and push
      // the bar past the window.
      expect(usage.slices[ContextUsageSlice.history], 300);
      expect(usage.usedChars, 5500);
    });

    test('a restored session reports the history it knows, and omits the rest', () {
      // Restoring gives the history back but not the system prompt the next
      // turn will build. Reporting that as 0 would show a free system prompt;
      // the key is left out so the card can say "not measured".
      final usage = PromptOptimizerAgent.measureContext(
        sessionWith(history: [LLMMessage(role: LLMRole.user, content: 'x' * 300)]),
        contextWindowTokens: 131072,
      );

      expect(usage.isUnknown, isFalse);
      expect(usage.slices.containsKey(ContextUsageSlice.systemPrompt), isFalse);
      expect(usage.slices.containsKey(ContextUsageSlice.tools), isFalse);
      expect(usage.slices[ContextUsageSlice.history], 300);
    });

    test('measures the history that will be sent, not the one on record', () {
      // Layer 1 elides bulky knowledge reads before the recent window. A
      // readout over the raw history would keep charging for content the model
      // no longer receives, and would never come back down.
      final history = <LLMMessage>[];
      for (int turn = 0; turn < 10; turn++) {
        history.add(LLMMessage(role: LLMRole.user, content: 'turn $turn'));
        history.add(LLMMessage(
          role: LLMRole.assistant,
          content: '',
          toolCalls: [
            LLMToolCall(id: 'c$turn', name: 'read_knowledge_file', arguments: {'path': 'a.md'}),
          ],
        ));
        history.add(LLMMessage(
          role: LLMRole.tool,
          content: jsonEncode({'path': 'a.md', 'page': 1, 'content': 'y' * 4000}),
          toolCallId: 'c$turn',
          toolName: 'read_knowledge_file',
        ));
      }

      final session = sessionWith(systemPromptChars: 100, history: history);
      final measured =
          PromptOptimizerAgent.measureContext(session, contextWindowTokens: 131072)
              .slices[ContextUsageSlice.history]!;
      final raw = PromptOptimizerAgent.occupiedChars('', session.history);

      expect(measured, lessThan(raw));
      // The last six user turns are protected; the four reads before them are
      // stubs of a couple of hundred chars each.
      expect(measured, lessThan(7 * 4000));
      expect(raw, greaterThan(9 * 4000));
    });

    test('a configured window is converted with the same ratio the budget uses', () {
      final usage = PromptOptimizerAgent.measureContext(
        sessionWith(systemPromptChars: 1000),
        contextWindowTokens: 100000,
      );
      expect(usage.basis, ContextWindowBasis.configured);
      expect(usage.windowChars, (100000 * ContextBudget.charsPerToken).round());
      expect(usage.remainingChars, usage.windowChars - 1000);
    });

    test('a calibrated session is measured against its own ratio', () {
      // Once the provider has billed a request, the window in *characters* is
      // known rather than assumed — a Chinese conversation genuinely fits fewer
      // of them, and the bar should fill faster to say so.
      final session = sessionWith(systemPromptChars: 1000)
        ..observedCharsPerToken = 1.2;
      final usage =
          PromptOptimizerAgent.measureContext(session, contextWindowTokens: 100000);

      expect(usage.windowChars, 120000);
      expect(
        usage.windowChars,
        lessThan((100000 * ContextBudget.charsPerToken).round()),
      );
    });

    test('an unset window is drawn against the default, and labelled as assumed', () {
      final usage = PromptOptimizerAgent.measureContext(
        sessionWith(systemPromptChars: 1000),
        contextWindowTokens: null,
      );
      expect(usage.basis, ContextWindowBasis.assumed);
      // The same assumption the compaction budget makes — the bar shows what
      // the app actually does, and the card says it is an assumption.
      expect(
        usage.windowChars,
        (ContextBudget.defaultWindowTokens * ContextBudget.charsPerToken).round(),
      );
    });

    test('an unlimited model has figures but no ceiling', () {
      final usage = PromptOptimizerAgent.measureContext(
        sessionWith(systemPromptChars: 1000, toolSchemaChars: 500),
        contextWindowTokens: 0,
      );
      expect(usage.basis, ContextWindowBasis.unlimited);
      expect(usage.hasWindow, isFalse);
      expect(usage.usedChars, 1500);
      // No window means no fraction to draw — and no division by zero either.
      expect(usage.fractionOf(ContextUsageSlice.systemPrompt), 0);
      expect(usage.remainingChars, 0);
    });

    test('an over-full window clamps instead of drawing past the track', () {
      final usage = PromptOptimizerAgent.measureContext(
        sessionWith(systemPromptChars: 100000),
        contextWindowTokens: 1000,
      );
      expect(usage.remainingChars, 0);
      expect(usage.fractionOf(ContextUsageSlice.systemPrompt), 1.0);
    });
  });

  group('toolSchemaChars', () {
    test('counts the schema, which is the bulk of it', () {
      final tool = LLMTool(
        name: 'read_knowledge_file',
        description: 'd' * 100,
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'p' * 200},
          },
        },
      );
      final chars = PromptOptimizerAgent.toolSchemaChars([tool]);
      expect(chars, greaterThan(300));
      expect(PromptOptimizerAgent.toolSchemaChars([tool, tool]), chars * 2);
    });

    test('withdrawing a tool makes the request smaller', () {
      // The agent drops read_knowledge_file once the window is exhausted; the
      // readout is recorded per request so it follows that down.
      expect(PromptOptimizerAgent.toolSchemaChars(const []), 0);
    });
  });

  group('recordRequestBasis', () {
    test('notifies only when the fixed cost actually changed', () {
      // It runs before every request of a turn, and the system prompt is built
      // once — a notify per request would rebuild the panel for nothing.
      final session = PromptOptimizerSession();
      int notifications = 0;
      session.addListener(() => notifications++);

      session.recordRequestBasis(systemPromptChars: 4000, toolSchemaChars: 1200);
      session.recordRequestBasis(systemPromptChars: 4000, toolSchemaChars: 1200);
      expect(notifications, 1);

      session.recordRequestBasis(systemPromptChars: 4000, toolSchemaChars: 900);
      expect(notifications, 2);
    });
  });
}
