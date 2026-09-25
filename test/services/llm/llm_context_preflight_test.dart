import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/context_budget.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// No request used to be checked against the model's context window before
/// sending (01 §6, 11 §A5): local stacks drop the prompt head and answer 200.
/// The check is a backstop — explicit windows only, a floor estimate, a margin.
void main() {
  LLMModelConfig config(int? window) => LLMModelConfig(
        modelId: 'local-llama',
        channelType: 'ollama',
        endpoint: 'http://127.0.0.1:11434/v1',
        apiKey: '',
        contextWindow: window,
      );

  List<LLMMessage> ofChars(int chars, {int images = 0}) => [
        LLMMessage(role: LLMRole.system, content: 's' * 10),
        LLMMessage(
          role: LLMRole.user,
          content: 'x' * (chars - 10),
          attachments: [
            for (var i = 0; i < images; i++)
              LLMAttachment.fromFile(File('img_$i.png'), 'image/png'),
          ],
        ),
      ];

  group('ContextBudget preflight', () {
    test('only a specified window is ever checked', () {
      expect(ContextBudget.exceedsWindow(1 << 30, null), isFalse);
      expect(ContextBudget.exceedsWindow(1 << 30, 0), isFalse);
      expect(ContextBudget.exceedsWindow(1 << 30, -1), isFalse);
      expect(ContextBudget.exceedsWindow(1 << 30, 4096), isTrue);
    });

    test('the margin: at 1.1 × window it passes, one token past it fails', () {
      const window = 10000;
      expect(ContextBudget.exceedsWindow(11000, window), isFalse);
      expect(ContextBudget.exceedsWindow(11001, window), isTrue);
      expect(ContextBudget.exceedsWindow(10500, window), isFalse);
    });

    test('the estimate is a floor: 6 chars per token, 258 per image', () {
      expect(ContextBudget.estimateRequestTokens(chars: 6000), 1000);
      expect(
          ContextBudget.estimateRequestTokens(
              chars: 6000, toolSchemaChars: 600, images: 2),
          1100 + 516);
    });

    test('no budget the assistant can reach trips it', () {
      // The largest occupancy layer 2 and the read cap allow is the whole
      // window in chars at the most permissive calibrated ratio.
      for (final window in [2048, 4096, 32768, 131072, 1000000]) {
        final maxOccupancy = ContextBudget.readCapChars(window, 0,
                observedCharsPerToken: 6.0) +
            ContextBudget.reserveFor(
                (window * 6.0).round());
        final estimate =
            ContextBudget.estimateRequestTokens(chars: maxOccupancy);
        expect(ContextBudget.exceedsWindow(estimate, window), isFalse,
            reason: 'window $window');
      }
    });
  });

  group('LLMService.preflightContextSize', () {
    test('a request clearly over an explicit window is refused with both '
        'numbers', () {
      final error = LLMService.preflightContextSize(
          config(4096), ofChars(60000), null);
      expect(error, isA<LLMContextSizeError>());
      expect(error!.contextWindow, 4096);
      expect(error.estimatedTokens, 10000);
      expect(error.toString(), contains('4096'));
      expect(LLMService.isRetryable(error), isFalse);
    });

    test('a request that fits is sent', () {
      expect(
          LLMService.preflightContextSize(config(4096), ofChars(20000), null),
          isNull);
    });

    test('unset and unlimited windows are never checked', () {
      expect(
          LLMService.preflightContextSize(config(null), ofChars(10000000), null),
          isNull);
      expect(
          LLMService.preflightContextSize(config(0), ofChars(10000000), null),
          isNull);
    });

    test('images and tool schemas count toward the estimate', () {
      // 24 000 chars = 4000 tokens: fits a 4096 window on its own…
      expect(
          LLMService.preflightContextSize(config(4096), ofChars(24000), null),
          isNull);
      // …but not with four images (+1032) on top.
      expect(
          LLMService.preflightContextSize(
              config(4096), ofChars(24000, images: 4), null),
          isNotNull);
      final bigTool = LLMTool(
        name: 'write_file',
        description: 'd' * 6000,
        parameters: const {'type': 'object'},
      );
      expect(
          LLMService.preflightContextSize(
              config(4096), ofChars(24000), [bigTool]),
          isNotNull);
    });

    test('tool-call arguments in the history are counted', () {
      final history = [
        LLMMessage(role: LLMRole.assistant, content: '', toolCalls: [
          LLMToolCall(
              id: 't1',
              name: 'write_knowledge_file',
              arguments: {'body': 'y' * 60000}),
        ]),
      ];
      expect(LLMService.preflightContextSize(config(4096), history, null),
          isNotNull);
    });
  });

  test('the resolver-facing config carries the window through withEndpoint',
      () {
    expect(config(8192).withEndpoint('http://x.invalid').contextWindow, 8192);
    // The output cap rides along too: every chat route on a vendor with
    // derived faces goes through withEndpoint, and a cap dropped there is
    // the exact symptom the setting exists to fix.
    final capped = LLMModelConfig(
        modelId: 'm', channelType: Vendors.openAIRest, endpoint: 'http://x.invalid', apiKey: 'k', maxOutputTokens: 32768);
    expect(capped.withEndpoint('http://y.invalid').maxOutputTokens, 32768);
  });
}
