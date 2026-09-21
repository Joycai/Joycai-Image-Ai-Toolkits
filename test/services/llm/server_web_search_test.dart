import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The host-run web search switch outside ④ (tools 05 §5, pitfalls 11 §A10):
/// DashScope's compatible face takes a top-level `enable_search`, its native
/// face `parameters.enable_search`. Neither returns sources on this app's
/// requests, so nothing is invented on the response side — the UI says so
/// instead. The switch is a vendor declaration per face, never a vendor-id
/// check, and the adapter refuses it on a face nobody declared: an unknown
/// top-level field is a 400 on api.openai.com.
void main() {
  ServerWebSearch support(String channelType, String modelId,
          {String? tag, String? wireProtocol}) =>
      LLMDispatcher.serverWebSearch(
        channelType: channelType,
        modelId: modelId,
        tag: tag,
        wireProtocol: wireProtocol,
      );

  group('LLMDispatcher.serverWebSearch', () {
    test('④ vendors declare a search tool whose sources come back', () {
      expect(support(Vendors.anthropicRest, 'claude-opus-5'),
          ServerWebSearch.withSources);
      expect(support(Vendors.minimaxAnthropic, 'MiniMax-M3'),
          ServerWebSearch.withSources);
    });

    test("Bailian's ① and native faces take the traceless switch", () {
      expect(support(Vendors.dashscope, 'qwen3-max'), ServerWebSearch.traceless);
      expect(support(Vendors.dashscopeNative, 'qwen3-max'),
          ServerWebSearch.traceless);
      expect(
          support(Vendors.dashscope, 'qwen3-max', wireProtocol: 'dashscope-chat'),
          ServerWebSearch.traceless);
      expect(
          support(Vendors.dashscopeNative, 'qwen3-max',
              wireProtocol: 'openai-chat'),
          ServerWebSearch.traceless);
    });

    test('the answer follows the face, not the vendor', () {
      // Bailian's ④ face is not declared: no switch is offered there.
      expect(
          support(Vendors.dashscope, 'qwen3-max', wireProtocol: 'anthropic-chat'),
          ServerWebSearch.unsupported);
    });

    test('everywhere else there is nothing to switch', () {
      expect(support(Vendors.openAIRest, 'gpt-5'), ServerWebSearch.unsupported);
      expect(support(Vendors.deepseek, 'deepseek-v4-pro'),
          ServerWebSearch.unsupported);
      expect(support(Vendors.officialGoogle, 'gemini-3-pro-preview'),
          ServerWebSearch.unsupported);
      expect(support(Vendors.midjourneyProxy, 'midjourney'),
          ServerWebSearch.unsupported);
    });

    test('a model that does not go down chat has none', () {
      expect(support(Vendors.anthropicRest, 'claude-opus-5', tag: 'image'),
          ServerWebSearch.unsupported);
      expect(support(Vendors.dashscope, 'qwen-image-3.0'),
          ServerWebSearch.unsupported);
    });
  });

  LLMTarget target(String channelType, String modelId,
      {bool webSearch = true, String? endpoint}) {
    final config = LLMModelConfig(
      modelId: modelId,
      channelType: channelType,
      endpoint: endpoint ?? 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      apiKey: 'k',
      enableWebSearch: webSearch,
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(channelType),
      model: ModelDescriptor.of(modelId),
    );
  }

  final hi = [LLMMessage(role: LLMRole.user, content: 'what happened today?')];

  group('① compatible face', () {
    Map<String, dynamic> payload(LLMTarget t) => OpenAIChatProtocol()
        .buildChatPayloadForTest(t, hi, isStreaming: false);

    test('a declared face sends top-level enable_search', () {
      expect(payload(target(Vendors.dashscope, 'qwen3-max'))['enable_search'],
          isTrue);
      expect(
          payload(target(Vendors.dashscopeNative, 'qwen3-max'))['enable_search'],
          isTrue);
    });

    test('switched off, nothing is sent', () {
      expect(
          payload(target(Vendors.dashscope, 'qwen3-max', webSearch: false))
              .containsKey('enable_search'),
          isFalse);
    });

    test('an undeclared vendor never sends it, whatever the stored flag says',
        () {
      // The flag travels with the model row (imports, channel-type changes);
      // the adapter is the second guard.
      for (final id in [Vendors.openAIRest, Vendors.deepseek, Vendors.minimax]) {
        expect(
            payload(target(id, 'm', endpoint: 'https://api.example.com/v1'))
                .containsKey('enable_search'),
            isFalse,
            reason: id);
      }
    });
  });

  group('native face', () {
    Map<String, dynamic> body(LLMTarget t) => buildDashScopeChatPayload(
          t,
          hi,
          multimodal: false,
          isStreaming: false,
        );

    test('the switch lives under parameters, not at the top level', () {
      final b = body(target(Vendors.dashscopeNative, 'qwen3-max',
          endpoint: 'https://dashscope.aliyuncs.com/api/v1'));
      expect((b['parameters'] as Map)['enable_search'], isTrue);
      expect(b.containsKey('enable_search'), isFalse);
    });

    test('switched off, nothing is sent', () {
      final b = body(target(Vendors.dashscopeNative, 'qwen3-max',
          webSearch: false, endpoint: 'https://dashscope.aliyuncs.com/api/v1'));
      expect((b['parameters'] as Map).containsKey('enable_search'), isFalse);
    });
  });

  group('④ face', () {
    List<dynamic>? tools(LLMTarget t) =>
        prepareAnthropicPayload(t, hi, isStreaming: false)['tools'] as List?;

    test('a ④ vendor sends the server tool', () {
      final declared = tools(target(Vendors.anthropicRest, 'claude-opus-5',
          endpoint: 'https://api.anthropic.com'));
      expect(declared, isNotNull);
      expect(declared!.single['name'], 'web_search');
    });

    test("a switch that travelled to Bailian's ④ face stays home", () {
      // The editor hides the switch there (serverWebSearch answers
      // unsupported); a flag stored while the model used another face used
      // to be sent anyway.
      expect(
        tools(target(Vendors.dashscope, 'qwen3-max',
            endpoint: 'https://dashscope.aliyuncs.com/apps/anthropic')),
        isNull,
      );
    });

    test('the payload and the editor ask the same question', () {
      for (final id in [Vendors.anthropicRest, Vendors.minimaxAnthropic, Vendors.dashscope]) {
        final vendor = Vendors.byId(id);
        expect(vendor.sendsWebSearchOn(WireProtocol.anthropicChat),
            vendor.webSearchOn(WireProtocol.anthropicChat) != ServerWebSearch.unsupported,
            reason: id);
      }
    });
  });

  group('a call that opts out of server tools', () {
    Map<String, dynamic> payload(LLMTarget t) => OpenAIChatProtocol()
        .buildChatPayloadForTest(t, hi, isStreaming: false);

    LLMTarget forCall(LLMTarget t, Map<String, dynamic>? options) => LLMTarget(
          config: LLMService.configForCall(t.config, options),
          vendor: t.vendor,
          model: t.model,
        );

    test('sends no search even when the model has it on', () {
      final t = target(Vendors.dashscope, 'qwen3-max');
      expect(payload(forCall(t, const {llmNoServerToolsKey: true}))
          .containsKey('enable_search'), isFalse);
      final anthropic = target(Vendors.anthropicRest, 'claude-opus-5',
          endpoint: 'https://api.anthropic.com');
      final body = prepareAnthropicPayload(
          forCall(anthropic, const {llmNoServerToolsKey: true}), hi,
          isStreaming: false);
      expect(body.containsKey('tools'), isFalse);
    });

    test('any other call keeps the model switch', () {
      final t = target(Vendors.dashscope, 'qwen3-max');
      expect(payload(forCall(t, const {'retryCount': 2}))['enable_search'],
          isTrue);
      expect(payload(forCall(t, null))['enable_search'], isTrue);
    });
  });
}
