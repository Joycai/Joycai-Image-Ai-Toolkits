import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/context_budget.dart';

/// Pins the tri-state encoding of `llm_models.context_window`, which two
/// unrelated consumers read (image batching and the Prompt Assistant's
/// budget) and which has no other written contract.
void main() {
  group('modeOf / store round-trip', () {
    test('null is "not set", not "unlimited"', () {
      // The dangerous confusion: an unset window must never be read as a
      // licence to send everything.
      expect(ContextBudget.modeOf(null), ContextWindowMode.unset);
    });

    test('0 and negatives are unlimited', () {
      expect(ContextBudget.modeOf(0), ContextWindowMode.unlimited);
      expect(ContextBudget.modeOf(-1), ContextWindowMode.unlimited);
    });

    test('a positive count is a real limit', () {
      expect(ContextBudget.modeOf(8192), ContextWindowMode.specified);
    });

    test('store encodes each mode back to the column', () {
      expect(ContextBudget.store(ContextWindowMode.unset, 8192), isNull);
      expect(ContextBudget.store(ContextWindowMode.unlimited, 8192), 0);
      expect(ContextBudget.store(ContextWindowMode.specified, 8192), 8192);
    });

    test('every mode survives store -> modeOf', () {
      for (final mode in ContextWindowMode.values) {
        expect(ContextBudget.modeOf(ContextBudget.store(mode, 65536)), mode);
      }
    });
  });

  group('budgetChars', () {
    test('scales with the window and the ratio', () {
      expect(ContextBudget.budgetChars(131072, 0.6),
          (131072 * 0.6 * ContextBudget.charsPerToken).round());
      // Halving the ratio halves the budget.
      expect(ContextBudget.budgetChars(131072, 0.3),
          ContextBudget.budgetChars(131072, 0.6) ~/ 2);
    });

    test('stays under the real window even if the text is pure CJK', () {
      // The failure this replaces: the old threshold assumed 4 chars/token, so
      // for a Chinese knowledge base the char budget mapped to several times
      // the model's actual token window and the request died before compaction
      // ever fired. Chinese costs ~1 token/char, so the char budget is the
      // worst-case token count and must still fit.
      for (final window in [4096, 8192, 32768, 131072, 1048576]) {
        expect(ContextBudget.budgetChars(window, 0.6), lessThan(window),
            reason: 'a $window-token model must not be handed a budget whose '
                'worst-case token cost exceeds the window');
      }
    });

    test('a bigger window earns a bigger budget', () {
      expect(ContextBudget.budgetChars(1048576, 0.6),
          greaterThan(ContextBudget.budgetChars(8192, 0.6)));
    });

    test('unset falls back to the conservative default window', () {
      expect(
          ContextBudget.budgetChars(null, 0.6),
          (ContextBudget.defaultWindowTokens * 0.6 * ContextBudget.charsPerToken)
              .round());
    });

    test('unlimited keeps the legacy threshold instead of collapsing to zero', () {
      // The trap: window * ratio is 0 when the window is 0, so a ratio trigger
      // would fire on literally every turn and summarize the conversation away.
      expect(ContextBudget.budgetChars(0, 0.6), ContextBudget.unlimitedBudgetChars);
      expect(ContextBudget.budgetChars(0, 0.6), greaterThan(0));
    });
  });

  group('readCapChars', () {
    test('spends the whole window, not just the summary ratio', () {
      // The headroom above the ratio is what pays for reading a file in one
      // piece; compaction reclaims it at the next turn boundary.
      final total = (131072 * ContextBudget.charsPerToken).round();
      expect(ContextBudget.readCapChars(131072, 0),
          total - ContextBudget.reserveFor(total));
      // Strictly more than the ratio alone would allow.
      expect(ContextBudget.readCapChars(131072, 0),
          greaterThan(ContextBudget.budgetChars(131072, 0.6)));
    });

    test('shrinks as the context fills', () {
      final empty = ContextBudget.readCapChars(131072, 0);
      final half = ContextBudget.readCapChars(131072, 100000);
      expect(half, empty - 100000);
    });

    test('never goes negative when the context is already over budget', () {
      expect(ContextBudget.readCapChars(4096, 999999), 0);
    });

    test('even the smallest window leaves room to read something', () {
      // Regression: a flat 16000-char reply reserve is ~8K tokens, so a
      // 4K-token model (8192 chars all in) went straight to zero and could
      // never read a knowledge file at all.
      expect(ContextBudget.readCapChars(4096, 0), greaterThan(2000));
      expect(ContextBudget.readCapChars(8192, 0),
          greaterThan(ContextBudget.readCapChars(4096, 0)));
    });

    test('the reply reserve scales down for small windows but is capped for big ones', () {
      expect(ContextBudget.reserveFor(8192), 2048);
      expect(ContextBudget.reserveFor(262144), ContextBudget.maxReplyReserveChars);
    });

    test('unlimited is capped anyway, and does not grow with occupancy', () {
      // "Unlimited" is the user's claim, not a fact, and progressive disclosure
      // protects output quality regardless of what fits.
      expect(ContextBudget.readCapChars(0, 0), ContextBudget.unlimitedReadCapChars);
      expect(ContextBudget.readCapChars(0, 500000), ContextBudget.unlimitedReadCapChars);
    });

    test('unset uses the conservative default window', () {
      final total =
          (ContextBudget.defaultWindowTokens * ContextBudget.charsPerToken).round();
      expect(ContextBudget.readCapChars(null, 0), total - ContextBudget.reserveFor(total));
    });
  });

  group('imageBatchSize', () {
    int batch(int? w) =>
        ContextBudget.imageBatchSize(w, defaultSize: 10, unlimitedSize: 1 << 30);

    test('preserves the behaviour the scraper had before delegating', () {
      expect(batch(null), 10);
      expect(batch(0), 1 << 30);
      expect(batch(8192), (8192 ~/ 512).clamp(4, 40));
    });

    test('stays inside the clamp at both extremes', () {
      expect(batch(4096), 8);
      expect(batch(1048576), 40);
    });
  });
}
