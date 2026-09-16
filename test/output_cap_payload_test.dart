import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_wire.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_responses_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The per-model output cap (`llm_models.max_output_tokens`) on every chat
/// wire. Every rule here fails silently when broken: a cap under the wrong
/// key is ignored by the host and the reply is cut at the host's default; a
/// cap sent when none was set changes a request that used to be
/// byte-identical; a probe whose one token loses to a stored 64K pays for a
/// generation.
void main() {
  final history = [LLMMessage(role: LLMRole.user, content: 'ping')];

  LLMTarget target(
    String channelType, {
    String modelId = 'some-model',
    int? maxOutputTokens,
    ReasoningEffort? effort,
    String endpoint = 'https://example.invalid/v1',
  }) {
    final config = LLMModelConfig(
      modelId: modelId,
      channelType: channelType,
      endpoint: endpoint,
      apiKey: 'k',
      maxOutputTokens: maxOutputTokens,
      reasoningEffort: effort,
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(channelType),
      model: ModelDescriptor.of(modelId),
    );
  }

  group('outputCapFor ranks its sources', () {
    test('nothing set is null', () {
      expect(outputCapFor(target(Vendors.openAIRest), null), isNull);
      expect(outputCapFor(target(Vendors.openAIRest), const {'retryCount': 2}),
          isNull);
    });

    test('the stored cap is used when no option asks', () {
      expect(
          outputCapFor(target(Vendors.openAIRest, maxOutputTokens: 65536), null),
          65536);
    });

    test('a per-request option beats the stored cap — the probe stays one token',
        () {
      expect(
        outputCapFor(target(Vendors.openAIRest, maxOutputTokens: 65536),
            const {'maxTokens': 1}),
        1,
      );
    });
  });

  group('① chat/completions', () {
    Map<String, dynamic> payload(LLMTarget t, [Map<String, dynamic>? options]) =>
        OpenAIChatProtocol()
            .buildChatPayloadForTest(t, history, options: options, isStreaming: false);

    test('no cap set sends neither spelling', () {
      final body = payload(target(Vendors.openAIRest));
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('max_completion_tokens'), isFalse);
    });

    test('OpenAI\'s own host takes the new spelling only', () {
      final body = payload(target(Vendors.openAIRest,
          maxOutputTokens: 32768, endpoint: 'https://api.openai.com/v1'));
      expect(body['max_completion_tokens'], 32768);
      expect(body.containsKey('max_tokens'), isFalse);
    });

    test('the generic profile on any other host — a custom relay — keeps the old spelling', () {
      final body = payload(target(Vendors.openAIRest, maxOutputTokens: 32768));
      expect(body['max_tokens'], 32768);
      expect(body.containsKey('max_completion_tokens'), isFalse);
    });

    test('every other ① host keeps the old spelling', () {
      for (final vendor in [
        Vendors.newApiOpenAI,
        Vendors.ollama,
        Vendors.lmStudio,
        Vendors.deepseek,
        Vendors.dashscope,
        Vendors.minimax,
      ]) {
        final body = payload(target(vendor, maxOutputTokens: 8192));
        expect(body['max_tokens'], 8192, reason: vendor);
        expect(body.containsKey('max_completion_tokens'), isFalse, reason: vendor);
      }
    });

    test('the probe\'s one token wins over the stored cap, under the host\'s key',
        () {
      final official = payload(
          target(Vendors.openAIRest, maxOutputTokens: 65536, endpoint: 'https://api.openai.com/v1'),
          const {'maxTokens': 1});
      expect(official['max_completion_tokens'], 1);
      final relay = payload(target(Vendors.openAIRest, maxOutputTokens: 65536), const {'maxTokens': 1});
      expect(relay['max_tokens'], 1);
    });
  });

  group('② responses', () {
    Map<String, dynamic> payload(LLMTarget t, [Map<String, dynamic>? options]) =>
        buildResponsesPayload(t, history, options: options, isStreaming: false);

    test('no cap set sends no max_output_tokens', () {
      expect(payload(target(Vendors.openAIResponsesRest))
          .containsKey('max_output_tokens'), isFalse);
    });

    test('the stored cap reaches max_output_tokens', () {
      expect(
          payload(target(Vendors.openAIResponsesRest, maxOutputTokens: 16384))[
              'max_output_tokens'],
          16384);
    });
  });

  group('③ generateContent', () {
    Map<String, dynamic> generationConfig(int? outputCap,
            [Map<String, dynamic>? options]) =>
        (prepareGooglePayload(history, options, null, outputCap: outputCap)[
                'generationConfig'] as Map)
            .cast<String, dynamic>();

    test('no cap sends no maxOutputTokens', () {
      expect(generationConfig(null).containsKey('maxOutputTokens'), isFalse);
    });

    test('the ranked cap reaches maxOutputTokens', () {
      expect(generationConfig(65536)['maxOutputTokens'], 65536);
    });

    test('a caller without a target still gets the raw option', () {
      expect(generationConfig(null, const {'maxTokens': 1})['maxOutputTokens'], 1);
    });
  });

  group('④ messages', () {
    Map<String, dynamic> payload(LLMTarget t,
            {Map<String, dynamic>? options, ThinkingDialect? dialect}) =>
        prepareAnthropicPayload(t, history,
            options: options, isStreaming: false, dialect: dialect);

    test('no cap set falls back to the built-in constant', () {
      expect(payload(target(Vendors.anthropicRest))['max_tokens'],
          anthropicDefaultMaxTokens);
    });

    test('the stored cap replaces the constant', () {
      expect(
          payload(target(Vendors.anthropicRest, maxOutputTokens: 65536))[
              'max_tokens'],
          65536);
    });

    test('the probe\'s one token wins over the stored cap', () {
      expect(
          payload(target(Vendors.anthropicRest, maxOutputTokens: 65536),
              options: const {'maxTokens': 1})['max_tokens'],
          1);
    });

    test('the budget dialect carves its half out of the raised cap', () {
      final body = payload(
        target(Vendors.anthropicRest,
            maxOutputTokens: 65536, effort: ReasoningEffort.medium),
        dialect: ThinkingDialect.anthropicBudget,
      );
      expect(body['max_tokens'], 65536);
      expect((body['thinking'] as Map)['budget_tokens'], 32768);
    });
  });

  group('C2 DashScope native', () {
    Map<String, dynamic> params(LLMTarget t, [Map<String, dynamic>? options]) =>
        (buildDashScopeChatPayload(t, history,
                options: options, multimodal: false, isStreaming: false)['parameters']
            as Map)
            .cast<String, dynamic>();

    test('no cap set sends no max_tokens', () {
      expect(params(target(Vendors.dashscopeNative)).containsKey('max_tokens'),
          isFalse);
    });

    test('the stored cap goes into parameters, not the top level', () {
      final t = target(Vendors.dashscopeNative, maxOutputTokens: 32768);
      expect(params(t)['max_tokens'], 32768);
      expect(
          buildDashScopeChatPayload(t, history,
              multimodal: false, isStreaming: false).containsKey('max_tokens'),
          isFalse);
    });
  });

  group('the deadline follows the cap', () {
    final dispatcher = LLMDispatcher();

    Duration deadline(LLMTarget t, [Map<String, dynamic>? options]) =>
        dispatcher.generateTimeout(t.config, options: options);

    test('a stored cap sizes the non-streaming deadline like a request option',
        () {
      final byOption = deadline(target(Vendors.openAIRest), const {'maxTokens': 65536});
      final byModel = deadline(target(Vendors.openAIRest, maxOutputTokens: 65536));
      expect(byModel, byOption);
      expect(byModel, greaterThan(deadline(target(Vendors.openAIRest))));
    });
  });
}
