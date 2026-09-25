import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';

/// ③'s reasoning control (reasoning 03 §2, docs/api/reasoning.md §1.4–1.5):
/// one generation's field, UPPERCASE levels, always with `includeThoughts`,
/// and nothing at all at the default effort.
void main() {
  group('layer 3 declares the field generation', () {
    GeminiThinkingGeneration gen(String id) => ModelFamilyClassifier.geminiThinkingGeneration(id);

    test('Gemini 3 and later take thinkingLevel', () {
      expect(gen('gemini-3-pro-preview'), GeminiThinkingGeneration.level);
      expect(gen('gemini-3.1-flash-lite'), GeminiThinkingGeneration.level);
      expect(gen('models/gemini-3.6-flash'), GeminiThinkingGeneration.level);
    });

    test('Gemini 2.5 takes thinkingBudget', () {
      expect(gen('gemini-2.5-pro'), GeminiThinkingGeneration.budget);
      expect(gen('gemini-2.5-flash-lite'), GeminiThinkingGeneration.budget);
    });

    test('older Gemini takes nothing', () {
      expect(gen('gemini-2.0-flash'), GeminiThinkingGeneration.none);
      expect(gen('gemini-1.5-pro'), GeminiThinkingGeneration.none);
    });

    test('an id with no readable version gets the loud guess', () {
      expect(gen('nano-thinker'), GeminiThinkingGeneration.level);
      expect(gen('gemini-flash-latest'), GeminiThinkingGeneration.level);
    });

    test('an image or video generator never takes it', () {
      expect(
        ModelDescriptor.of('gemini-3.1-flash-image').geminiThinking,
        GeminiThinkingGeneration.none,
      );
      expect(ModelDescriptor.of('veo-3.0-generate').geminiThinking, GeminiThinkingGeneration.none);
      expect(
        ModelDescriptor.of('gemini-3-pro-preview').geminiThinking,
        GeminiThinkingGeneration.level,
      );
    });
  });

  group('translation table', () {
    test('default and non-thinking models send nothing', () {
      expect(geminiThinkingConfig(GeminiThinkingGeneration.level, null), isNull);
      expect(geminiThinkingConfig(GeminiThinkingGeneration.none, ReasoningEffort.high), isNull);
    });

    test('levels are UPPERCASE; off is MINIMAL, max is HIGH', () {
      String? level(ReasoningEffort e) =>
          geminiThinkingConfig(GeminiThinkingGeneration.level, e)?['thinkingLevel'];
      expect(level(ReasoningEffort.off), 'MINIMAL');
      expect(level(ReasoningEffort.low), 'LOW');
      expect(level(ReasoningEffort.medium), 'MEDIUM');
      expect(level(ReasoningEffort.high), 'HIGH');
      expect(level(ReasoningEffort.max), 'HIGH');
    });

    test('budgets: off is 0, max is high', () {
      int? budget(ReasoningEffort e) =>
          geminiThinkingConfig(GeminiThinkingGeneration.budget, e)?['thinkingBudget'];
      expect(budget(ReasoningEffort.off), 0);
      expect(budget(ReasoningEffort.low), 1024);
      expect(budget(ReasoningEffort.medium), 8192);
      expect(budget(ReasoningEffort.high), 24576);
      expect(budget(ReasoningEffort.max), 24576);
    });

    test('exactly one generation field, always with includeThoughts', () {
      for (final gen in [GeminiThinkingGeneration.level, GeminiThinkingGeneration.budget]) {
        for (final e in ReasoningEffort.values) {
          final c = geminiThinkingConfig(gen, e)!;
          expect(c['includeThoughts'], isTrue, reason: '$gen $e');
          expect(
            c.containsKey('thinkingLevel') ^ c.containsKey('thinkingBudget'),
            isTrue,
            reason: '$gen $e',
          );
        }
      }
    });
  });

  group('prepareGooglePayload', () {
    final history = [LLMMessage(role: LLMRole.user, content: 'hi')];

    Map generationConfig(
      GeminiThinkingGeneration thinking,
      ReasoningEffort? effort, {
      bool emitsImages = false,
    }) =>
        prepareGooglePayload(
              history,
              null,
              null,
              thinking: thinking,
              reasoningEffort: effort,
              emitsImages: emitsImages,
            )['generationConfig']
            as Map;

    test('the default effort sends the same body as before', () {
      expect(generationConfig(GeminiThinkingGeneration.level, null), isEmpty);
      expect(
        prepareGooglePayload(history, null, null, thinking: GeminiThinkingGeneration.level),
        prepareGooglePayload(history, null, null),
      );
    });

    test('a level lands under generationConfig.thinkingConfig', () {
      expect(generationConfig(GeminiThinkingGeneration.level, ReasoningEffort.high), {
        'thinkingConfig': {'thinkingLevel': 'HIGH', 'includeThoughts': true},
      });
    });

    test('a budget lands there too, and only the budget', () {
      final c = generationConfig(
        GeminiThinkingGeneration.budget,
        ReasoningEffort.low,
      )['thinkingConfig'];
      expect(c, {'thinkingBudget': 1024, 'includeThoughts': true});
    });

    test('a model that does not think gets no thinkingConfig', () {
      expect(
        generationConfig(GeminiThinkingGeneration.none, ReasoningEffort.high, emitsImages: true),
        {
          'responseModalities': ['TEXT', 'IMAGE'],
        },
      );
    });
  });
}
