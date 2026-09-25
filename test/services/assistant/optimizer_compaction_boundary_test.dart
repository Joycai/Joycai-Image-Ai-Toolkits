import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// Standard 10 §3.1: compaction triggers at the budget but folds toward a
/// lower retention target, so the turn after a compaction does not trigger it
/// again — every re-summary invalidates the prompt-cache prefix.
void main() {
  usePrivateDataDir('joycai_compaction_boundary_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  /// [turns] finished turns: a short user message and an assistant reply of
  /// [chars] characters each.
  List<LLMMessage> history(int turns, int chars, {bool summaryFirst = false}) => [
    if (summaryFirst)
      LLMMessage(role: LLMRole.user, content: '${PromptOptimizerAgent.summaryMarker}\nearlier'),
    for (var i = 1; i <= turns; i++) ...[
      LLMMessage(role: LLMRole.user, content: 'turn $i'),
      LLMMessage(role: LLMRole.assistant, content: 'x' * chars),
    ],
  ];

  /// Index of the [n]th (1-based) real user turn in [h].
  int turnStart(List<LLMMessage> h, int n) {
    var seen = 0;
    for (var i = 0; i < h.length; i++) {
      if (h[i].role == LLMRole.user && h[i].content.startsWith('turn ')) {
        if (++seen == n) return i;
      }
    }
    throw StateError('no turn $n');
  }

  int? boundary(List<LLMMessage> h, {required int budget, bool sizeTriggered = true}) =>
      PromptOptimizerAgent.compactionBoundary(
        h,
        systemPrompt: '',
        budgetChars: budget,
        sizeTriggered: sizeTriggered,
      );

  group('compactionBoundary', () {
    test('a message-count trigger folds to the recent window, as before', () {
      final h = history(10, 50);
      expect(
        boundary(h, budget: 1 << 30, sizeTriggered: false),
        turnStart(h, 5),
        reason: 'the last six turns are kept',
      );
    });

    test('small recent turns: the six-turn window already reaches the target', () {
      final h = history(10, 100);
      expect(boundary(h, budget: 5000), turnStart(h, 5));
    });

    test('bulky recent turns: fold further, keeping as many as fit the target', () {
      // Each turn is ~507 chars and the summary allowance is 1500, so three
      // kept turns project to ~3020 — under 5000 × 0.45/0.7 ≈ 3214 — and
      // four to ~3530, over it.
      final h = history(10, 500);
      expect(boundary(h, budget: 5000), turnStart(h, 8));
    });

    test('nothing fits the target: best effort keeps the two-turn floor', () {
      final h = history(10, 3000);
      expect(boundary(h, budget: 5000), turnStart(h, 9));
    });

    test('an existing summary plus one turn is not worth re-summarizing', () {
      final h = history(3, 3000, summaryFirst: true);
      expect(boundary(h, budget: 5000), isNull);
    });

    test('without a summary, a single bulky turn may still be folded', () {
      final h = history(3, 3000);
      expect(boundary(h, budget: 5000), turnStart(h, 2));
    });

    test('two turns or fewer: nothing to fold', () {
      expect(boundary(history(2, 3000), budget: 5000), isNull);
      expect(boundary(history(1, 3000), budget: 5000), isNull);
    });
  });

  test('the turn after a compaction does not compact again', () async {
    // Bulky enough that the old six-turn fold stays over budget (~12K chars
    // kept, plus the system prompt, against 9000) while the two-turn fold the
    // target forces drops well under it.
    final session = PromptOptimizerSession();
    for (final m in history(10, 2000)) {
      session.history.add(m);
    }
    session.addUserTurn('pending');
    var summaries = 0;
    final tags = <Object?>[];
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      if (messages.first.content.startsWith('You compress')) {
        summaries++;
        tags.add(options['usageTag']);
        return LLMResponse(text: 'short summary');
      }
      return LLMResponse(text: 'ok');
    };

    // contextWindow 10000 tokens × 0.6 × 1.5 chars/token = a 9000-char budget.
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
      contextWindow: 10000,
    );
    expect(summaries, 1);
    expect(tags, ['compaction'], reason: 'compaction spend is attributable in the usage table');

    session.addUserTurn('follow-up');
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
      contextWindow: 10000,
    );
    expect(summaries, 1, reason: 'folding to the target left headroom below the trigger');
  });
}
