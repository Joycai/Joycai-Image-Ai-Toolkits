import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/context_budget.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// The assistant's context accounting: what counts as occupied, when the
/// conversation gets summarized, and how the char/token ratio is calibrated.
void main() {
  group('occupiedChars', () {
    test('counts the system prompt, which is re-sent in full every request', () {
      // The knowledge-base file map lives in the system prompt and is neither
      // elided nor compacted, so a history-only tally understates the context
      // by however large the user's README.md is.
      expect(PromptOptimizerAgent.occupiedChars('x' * 500, const []), 500);
    });

    test('counts tool-call arguments, not just message text', () {
      // A staged write_knowledge_file carries a whole file body in the
      // assistant message's arguments; content-only counting misses all of it.
      final withBody = PromptOptimizerAgent.occupiedChars('', [
        LLMMessage(
          role: LLMRole.assistant,
          content: '',
          toolCalls: [
            LLMToolCall(
              id: 'c1',
              name: 'write_knowledge_file',
              arguments: {'path': 'a.md', 'content': 'y' * 5000},
            ),
          ],
        ),
      ]);
      expect(withBody, greaterThan(5000));
    });

    test('charges for attachments even though they carry no characters', () {
      final bare = PromptOptimizerAgent.occupiedChars(
          '', [LLMMessage(role: LLMRole.user, content: 'look')]);
      final withImage = PromptOptimizerAgent.occupiedChars('', [
        LLMMessage(
          role: LLMRole.user,
          content: 'look',
          attachments: [LLMAttachment.fromBytes(null, 'image/png')],
        ),
      ]);
      expect(withImage, greaterThan(bare + 1000));
    });
  });

  group('shouldCompact', () {
    test('fires once occupancy reaches the budget', () {
      expect(
          PromptOptimizerAgent.shouldCompact(
              occupied: 999, budgetChars: 1000, messageCount: 1),
          isFalse);
      expect(
          PromptOptimizerAgent.shouldCompact(
              occupied: 1000, budgetChars: 1000, messageCount: 1),
          isTrue);
    });

    test('message count is an independent trigger', () {
      // A long conversation of short turns costs little context but still
      // slows every request down.
      expect(
          PromptOptimizerAgent.shouldCompact(
              occupied: 0, budgetChars: 1000000, messageCount: 500),
          isTrue);
    });

    test('an unlimited model does not summarize on every single turn', () {
      // The trap: window * ratio is 0 for an unlimited model, and `occupied >= 0`
      // is always true, so a naive ratio trigger would summarize the whole
      // conversation away every turn.
      final budget = ContextBudget.budgetChars(0, 0.6);
      expect(
          PromptOptimizerAgent.shouldCompact(
              occupied: 5000, budgetChars: budget, messageCount: 1),
          isFalse);
    });

    test('a real window drives the trigger, unlike the old fixed threshold', () {
      // Same occupancy, different models: the small one must summarize and the
      // big one must not. Before this, both used one hardcoded 192000.
      const occupied = 20000;
      expect(
          PromptOptimizerAgent.shouldCompact(
              occupied: occupied,
              budgetChars: ContextBudget.budgetChars(8192, 0.6),
              messageCount: 1),
          isTrue);
      expect(
          PromptOptimizerAgent.shouldCompact(
              occupied: occupied,
              budgetChars: ContextBudget.budgetChars(1048576, 0.6),
              messageCount: 1),
          isFalse);
    });
  });

  group('promptTokensOf', () {
    test('reads both provider spellings', () {
      expect(LLMService.promptTokensOf({'promptTokenCount': 1234}), 1234);
      expect(LLMService.promptTokensOf({'prompt_tokens': 1234}), 1234);
      expect(LLMService.promptTokensOf({'prompt_tokens': '1234'}), 1234);
    });

    test('a provider that reports nothing is null, never zero', () {
      // OpenAI-compatible `usage` is optional and llama.cpp/LM Studio omit it.
      // Reading absent as zero would say "the context is empty" on exactly the
      // small local models that overflow first.
      expect(LLMService.promptTokensOf({}), isNull);
      expect(LLMService.promptTokensOf({'finish_reason': 'stop'}), isNull);
      expect(LLMService.promptTokensOf({'prompt_tokens': 0}), isNull);
      expect(LLMService.promptTokensOf({'prompt_tokens': 'garbage'}), isNull);
    });
  });

  group('calibrate', () {
    test('recovers the real ratio from what the provider billed', () {
      // 4 chars/token — an English conversation.
      expect(ContextBudget.calibrate(charsSent: 40000, promptTokens: 10000), 4.0);
      // ~1.2 chars/token — a Chinese one. One constant cannot serve both.
      expect(ContextBudget.calibrate(charsSent: 12000, promptTokens: 10000),
          closeTo(1.2, 0.001));
    });

    test('falls back to null when the provider reported nothing', () {
      expect(ContextBudget.calibrate(charsSent: 40000, promptTokens: null), isNull);
      expect(ContextBudget.calibrate(charsSent: 0, promptTokens: 10), isNull);
    });

    test('clamps nonsense instead of unbounding the budget', () {
      expect(ContextBudget.calibrate(charsSent: 1000000, promptTokens: 1), 6.0);
      expect(ContextBudget.calibrate(charsSent: 1, promptTokens: 1000000), 0.5);
    });

    test('a calibrated ratio round-trips through the budget', () {
      // The property that makes this safe: budget_chars / observed is the token
      // budget we meant, whatever the content actually costs.
      const window = 131072;
      const ratio = 0.6;
      final observed =
          ContextBudget.calibrate(charsSent: 12000, promptTokens: 10000)!;
      final budget = ContextBudget.budgetChars(window, ratio,
          observedCharsPerToken: observed);
      expect(budget / observed, closeTo(window * ratio, 1));
    });

    test('a Chinese session ends up with a tighter budget than the default', () {
      final chinese = ContextBudget.calibrate(charsSent: 12000, promptTokens: 10000);
      final english = ContextBudget.calibrate(charsSent: 40000, promptTokens: 10000);
      expect(
          ContextBudget.budgetChars(131072, 0.6, observedCharsPerToken: chinese),
          lessThan(ContextBudget.budgetChars(131072, 0.6)));
      expect(
          ContextBudget.budgetChars(131072, 0.6, observedCharsPerToken: english),
          greaterThan(ContextBudget.budgetChars(131072, 0.6)));
    });
  });
}
