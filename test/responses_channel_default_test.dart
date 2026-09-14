import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';

/// A channel can default to the Responses API as a whole: two channel types
/// that are [Vendors.openAIRest] / [Vendors.newApiOpenAI] with the chat menu
/// reversed. What must hold is that the reversal moves exactly the chat
/// default — no model is re-described, media routes stay put, and Chat
/// Completions remains a valid per-model pin.
void main() {
  const responsesLed = [Vendors.openAIResponsesRest, Vendors.newApiOpenAIResponses];
  const chatLed = {
    Vendors.openAIResponsesRest: Vendors.openAIRest,
    Vendors.newApiOpenAIResponses: Vendors.newApiOpenAI,
  };

  group('Responses-led channel types', () {
    test('lead with Responses and keep Chat Completions on the menu', () {
      for (final id in responsesLed) {
        expect(Vendors.byId(id).id, id, reason: '$id must be registered');
        expect(Vendors.byId(id).menuFor(Surface.chat),
            [WireProtocol.openaiResponses, WireProtocol.openaiChat],
            reason: id);
      }
      // The existing types are untouched.
      for (final id in chatLed.values) {
        expect(Vendors.byId(id).menuFor(Surface.chat).first,
            WireProtocol.openaiChat,
            reason: id);
      }
    });

    test('route an unpinned chat model to Responses', () {
      for (final id in responsesLed) {
        expect(LLMDispatcher.autoProtocolFor(id, 'gpt-5.6-sol'),
            WireProtocol.openaiResponses,
            reason: id);
        expect(
            LLMDispatcher.resolvedChatFace(
                channelType: id, modelId: 'gpt-5.6-sol', tag: 'multimodal'),
            WireProtocol.openaiResponses,
            reason: id);
      }
    });

    test('still accept a Chat Completions pin', () {
      for (final id in responsesLed) {
        expect(
            LLMDispatcher.isStaleProtocolSelection(
                id, 'gpt-5.6-sol', WireProtocol.openaiChat.id),
            isFalse,
            reason: id);
        expect(
            LLMDispatcher.resolvedChatFace(
                channelType: id,
                modelId: 'gpt-5.6-sol',
                wireProtocol: WireProtocol.openaiChat.id),
            WireProtocol.openaiChat,
            reason: id);
      }
    });

    test('describe an unpinned model exactly as its id does', () {
      for (final id in responsesLed) {
        for (final model in ['gpt-5.6-sol', 'o3-mini', 'gpt-4o']) {
          expect(
              identical(
                  LLMDispatcher.descriptorFor(channelType: id, modelId: model),
                  ModelDescriptor.of(model)),
              isTrue,
              reason: '$model on $id');
        }
      }
    });

    test('leave image and video routes where the chat-led sibling has them',
        () {
      for (final entry in chatLed.entries) {
        for (final (model, tag) in [
          ('gpt-image-1', 'image'),
          ('nano-banana-pro', 'image'),
          ('sora-2', 'video'),
        ]) {
          expect(LLMDispatcher.autoProtocolFor(entry.key, model, tag: tag),
              LLMDispatcher.autoProtocolFor(entry.value, model, tag: tag),
              reason: '$model on ${entry.key}');
          expect(LLMDispatcher.protocolMenu(entry.key, model, tag: tag).options,
              LLMDispatcher.protocolMenu(entry.value, model, tag: tag).options,
              reason: '$model on ${entry.key}');
        }
      }
    });
  });

  group('presets', () {
    test('OpenAI official switches between the two chat interfaces', () {
      final responses = presetForChannelType(Vendors.openAIResponsesRest,
          endpoint: 'https://api.openai.com/v1');
      expect(responses?.id, 'openai-official');
      expect(variantForChannelType(responses!, Vendors.openAIResponsesRest)?.id,
          'responses');

      final chat = presetForChannelType(Vendors.openAIRest,
          endpoint: 'https://api.openai.com/v1');
      expect(chat?.id, 'openai-official');
      expect(variantForChannelType(chat!, Vendors.openAIRest)?.id, 'chat');
      // Both variants keep the same address: the switch rewrites nothing.
      expect(chat.variants.map((v) => v.defaultEndpoint).toSet(),
          {'https://api.openai.com/v1'});
    });

    test('New API offers a Responses format on the same /v1 suffix', () {
      final preset = presetForChannelType(Vendors.newApiOpenAIResponses,
          endpoint: 'https://relay.example.com/v1');
      expect(preset?.id, 'newapi');
      final variant = variantForChannelType(preset!, Vendors.newApiOpenAIResponses);
      expect(variant?.id, 'openai-responses');
      expect(variant?.endpointSuffix, '/v1');
    });
  });
}
