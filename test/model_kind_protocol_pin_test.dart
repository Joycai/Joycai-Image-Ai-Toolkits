import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the model-kind declaration and media protocol selection (the 2026-09
/// round; plan retired, see docs/plans/README.md).
///
/// The problem this exists for: a relay names its models freely, so routing
/// by id sent `nano-banana-pro` through chat with no way to say otherwise,
/// and hid `my-sora` from the video picker altogether. The model's kind
/// (`llm_models.tag`) now declares the surface and a selection on that
/// surface's menu decides the route — while every model whose kind agrees
/// with its id, and carries no selection, must route exactly as before.
void main() {
  final dispatcher = LLMDispatcher();

  LLMModelConfig config(String modelId, String channelType,
          {String? tag, String? wireProtocol}) =>
      LLMModelConfig(
        modelId: modelId,
        channelType: channelType,
        endpoint: 'https://relay.example.com/v1',
        apiKey: 'k',
        tag: tag,
        wireProtocol: wireProtocol,
      );

  ModelDescriptor served(String modelId, String channelType,
          {String? tag, String? wireProtocol}) =>
      dispatcher
          .resolveTarget(config(modelId, channelType,
              tag: tag, wireProtocol: wireProtocol))
          .model;

  List<String> imageKeys(ModelCapabilities c) =>
      c.imageParams.map((p) => p.key).toList();
  List<String> videoKeys(ModelCapabilities c) =>
      c.videoParams.map((p) => p.key).toList();

  group('the kind declares the surface', () {
    test('a tag overrides what the id classifies as', () {
      expect(LLMDispatcher.surfaceForModel('nano-banana-pro'), Surface.chat);
      expect(LLMDispatcher.surfaceForModel('nano-banana-pro', tag: 'image'),
          Surface.imageGen);
      expect(LLMDispatcher.surfaceForModel('my-sora', tag: 'video'),
          Surface.videoJob);
      expect(LLMDispatcher.surfaceForModel('gpt-image-1', tag: 'chat'),
          Surface.chat);
    });

    test('multimodal and refiner are chat; no tag falls back to the id', () {
      expect(LLMDispatcher.surfaceForModel('gemini-2.5-flash-image',
          tag: 'multimodal'), Surface.chat);
      expect(LLMDispatcher.surfaceForModel('gpt-image-1', tag: 'refiner'),
          Surface.chat);
      expect(LLMDispatcher.surfaceForModel('gpt-image-1', tag: ''),
          Surface.imageGen);
    });
  });

  group('a kind that agrees with the id changes nothing', () {
    // The regression gate. Kinds are written by inferTag at discovery, so
    // this is the state of nearly every stored row: if reading the tag moved
    // any of them, it would move silently.
    const ids = [
      'gpt-image-1',
      'gpt-image-2',
      'gemini-2.5-flash-image',
      'imagen-4.0',
      'qwen-image-3.0',
      'wan2.7-image',
      'image-01',
      'grok-imagine-image',
      'mj_imagine',
      'sora-2',
      'veo-3.0',
      'wan3.0-video',
      'MiniMax-H3',
      'MiniMaxAI/MiniMax-H3',
      'gpt-4o',
      'qwen-max',
      'claude-sonnet-4-5',
      'nano-banana-pro',
    ];

    test('same descriptor and same auto, on every vendor', () {
      for (final vendor in Vendors.all) {
        for (final id in ids) {
          final tag = ModelFamilyClassifier.inferTag(id);
          final reason = '$id (tag $tag) on ${vendor.id}';
          expect(identical(served(id, vendor.id, tag: tag), served(id, vendor.id)),
              isTrue,
              reason: reason);
          expect(LLMDispatcher.autoProtocolFor(vendor.id, id, tag: tag),
              LLMDispatcher.autoProtocolFor(vendor.id, id),
              reason: reason);
        }
      }
    });

    test('and with no selection the descriptor is the id\'s own', () {
      for (final vendor in Vendors.all) {
        for (final id in ids) {
          // The one deliberate exception: a Veo id on a non-Gemini channel
          // was refused outright, and now takes the channel's video surface.
          // Every other pair must be the very object the id resolves to.
          if (ModelDescriptor.of(id).family == ModelFamily.geminiVideo &&
              vendor.family != ProtocolFamily.gemini) {
            continue;
          }
          expect(identical(served(id, vendor.id), ModelDescriptor.of(id)),
              isTrue,
              reason: '$id on ${vendor.id}');
        }
      }
    });
  });

  group('relay image models', () {
    test('an unrecognized alias tagged image gets a menu and draws through chat',
        () {
      final menu = LLMDispatcher.protocolMenu(
          Vendors.openAIRest, 'nano-banana-pro',
          tag: 'image');
      expect(menu.options, [WireProtocol.openaiImages, WireProtocol.chatImage]);
      expect(menu.auto, WireProtocol.chatImage);

      final model = served('nano-banana-pro', Vendors.openAIRest, tag: 'image');
      // An image generator on the chat wire: without the flag, a reply that
      // is a bare image link is taken as a citation and never downloaded.
      expect(model.capabilities.isImageGenerator, isTrue);
      expect(model.capabilities.imageParams, isEmpty);
    });

    test('pinned to the Images API, it routes there with its parameters', () {
      final pinned = config('nano-banana-pro', Vendors.openAIRest,
          tag: 'image', wireProtocol: 'openai-images');
      final model = dispatcher.resolveTarget(pinned).model;
      expect(model.family, ModelFamily.openaiImage);
      expect(imageKeys(model.capabilities),
          imageKeys(ModelCapabilities.forModel('gpt-image-1')));
      // Single-shot is the Images API branch's signature.
      expect(dispatcher.streamIsSingleShot(pinned), isTrue);
      expect(dispatcher.streamIsSingleShot(
              config('nano-banana-pro', Vendors.openAIRest, tag: 'image')),
          isFalse);
    });

    test('gpt-image-1 can be sent through chat, and is not by default', () {
      expect(
          dispatcher.streamIsSingleShot(
              config('gpt-image-1', Vendors.openAIRest, tag: 'image')),
          isTrue);
      final viaChat = config('gpt-image-1', Vendors.openAIRest,
          tag: 'image', wireProtocol: 'chat-image');
      expect(dispatcher.streamIsSingleShot(viaChat), isFalse);
      expect(dispatcher.resolveTarget(viaChat).model.family, ModelFamily.other);
    });

    test('pinning the route auto already takes keeps the id\'s table', () {
      // qwen-image on a relay rides chat on auto. Naming that route
      // explicitly must not strip the DashScope table — or the generation-
      // sized deadline that comes with it.
      final auto = config('qwen-image-3.0', Vendors.openAIRest, tag: 'image');
      final pinned = config('qwen-image-3.0', Vendors.openAIRest,
          tag: 'image', wireProtocol: 'chat-image');
      expect(identical(dispatcher.resolveTarget(pinned).model,
              ModelDescriptor.of('qwen-image-3.0')),
          isTrue);
      expect(dispatcher.generateTimeout(pinned), dispatcher.generateTimeout(auto));
    });

    test('Imagen through chat stays a Gemini family', () {
      // The OpenAI-compatible chat wire adds its Gemini extensions by family;
      // demoting to `other` would drop them without a sound.
      final model = ModelDescriptor.of('imagen-4.0',
          servedBy: WireProtocol.chatImage);
      expect(model.family, ModelFamily.geminiChat);
      expect(model.isGeminiFamily, isTrue);
    });
  });

  group('relay video models', () {
    test('an unrecognized alias tagged video reaches the video surface', () {
      final tagged = config('my-sora', Vendors.openAIRest, tag: 'video');
      expect(LLMDispatcher.autoProtocolFor(Vendors.openAIRest, 'my-sora',
          tag: 'video'), WireProtocol.openaiVideos);
      expect(dispatcher.canRunVideoJob(tagged), isTrue);
      final model = dispatcher.resolveTarget(tagged).model;
      expect(model.family, ModelFamily.openaiVideo);
      expect(videoKeys(model.capabilities),
          videoKeys(ModelCapabilities.forModel('sora-2')));
    });

    test('without the video kind it stays out of the picker', () {
      expect(dispatcher.canRunVideoJob(
          config('my-sora', Vendors.openAIRest, tag: 'chat')), isFalse);
      expect(dispatcher.canRunVideoJob(config('my-sora', Vendors.openAIRest)),
          isFalse);
    });

    test('a kind of chat on a recognized video id takes it off the video route',
        () {
      expect(dispatcher.canRunVideoJob(config('sora-2', Vendors.openAIRest)),
          isTrue);
      expect(dispatcher.canRunVideoJob(
          config('sora-2', Vendors.openAIRest, tag: 'chat')), isFalse);
    });
  });

  group('channels without generic media surfaces', () {
    test('an Anthropic relay offers only chat for images, nothing for video',
        () {
      final image = LLMDispatcher.protocolMenu(
          Vendors.newApiAnthropic, 'img-fast',
          tag: 'image');
      expect(image.options, [WireProtocol.chatImage]);
      expect(image.auto, WireProtocol.chatImage);

      final video = LLMDispatcher.protocolMenu(
          Vendors.newApiAnthropic, 'my-sora',
          tag: 'video');
      expect(video.options, isEmpty);
      expect(video.auto, isNull);
      expect(video.fixed, isFalse);
      expect(dispatcher.canRunVideoJob(
          config('my-sora', Vendors.newApiAnthropic, tag: 'video')), isFalse);
    });

    test("DeepSeek keeps today's route for a recognized id and nothing more",
        () {
      final menu =
          LLMDispatcher.protocolMenu(Vendors.deepseek, 'sora-2', tag: 'video');
      expect(menu.auto, WireProtocol.openaiVideos);
      expect(menu.options, [WireProtocol.openaiVideos]);
      expect(LLMDispatcher.protocolMenu(Vendors.deepseek, 'my-sora',
          tag: 'video').auto, isNull);
    });

    test('the local runtimes stay closed until their docs are checked', () {
      for (final vendor in [Vendors.ollama, Vendors.lmStudio]) {
        expect(
            LLMDispatcher.protocolMenu(vendor, 'flux-local', tag: 'image')
                .options,
            [WireProtocol.chatImage],
            reason: vendor);
      }
    });

    test('xAI answers an unrecognized video model with its own surface', () {
      final tagged = config('grok-next', Vendors.xaiApi, tag: 'video');
      expect(LLMDispatcher.autoProtocolFor(Vendors.xaiApi, 'grok-next',
          tag: 'video'), WireProtocol.xaiVideos);
      expect(dispatcher.canRunVideoJob(tagged), isTrue);
    });

    test('Midjourney is a fixed route, not a missing one', () {
      final menu = LLMDispatcher.protocolMenu(
          Vendors.midjourneyProxy, 'mj_imagine',
          tag: 'image');
      expect(menu.fixed, isTrue);
      expect(menu.options, isEmpty);
    });
  });

  group('first-party vendors', () {
    test('a DashScope model the classifier has not met can be pinned native',
        () {
      final menu = LLMDispatcher.protocolMenu(
          Vendors.dashscope, 'wan3.5-image',
          tag: 'image');
      expect(menu.options, [
        WireProtocol.dashscopeImagesSync,
        WireProtocol.dashscopeImagesAsync,
        WireProtocol.chatImage,
      ]);
      expect(menu.auto, WireProtocol.chatImage);

      final pinned = config('wan3.5-image', Vendors.dashscope,
          tag: 'image', wireProtocol: 'dashscope-images-sync');
      final model = dispatcher.resolveTarget(pinned).model;
      expect(model.family, ModelFamily.dashscopeImage);
      expect(model.capabilities.longRunning, isTrue);
      expect(dispatcher.streamIsSingleShot(pinned), isTrue);
    });

    test("MiniMax's image surface is offered for, not forced on, qwen-image",
        () {
      final menu = LLMDispatcher.protocolMenu(Vendors.minimax, 'qwen-image',
          tag: 'image');
      expect(menu.auto, WireProtocol.chatImage);
      expect(menu.options, contains(WireProtocol.minimaxImages));

      final pinned = config('qwen-image', Vendors.minimax,
          tag: 'image', wireProtocol: 'minimax-images');
      expect(dispatcher.resolveTarget(pinned).model.family,
          ModelFamily.minimaxImage);
      expect(dispatcher.streamIsSingleShot(pinned), isTrue);
    });
  });

  group('staleness and the cache', () {
    test('changing the kind strands a selection on the old surface', () {
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'wan2.7-image', 'dashscope-images-async',
              tag: 'image'),
          isFalse);
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'wan2.7-image', 'dashscope-images-async',
              tag: 'chat'),
          isTrue);
      // And a stale selection routes as auto.
      expect(
          dispatcher.generateTimeout(config('wan2.7-image', Vendors.dashscope,
              tag: 'chat', wireProtocol: 'dashscope-images-async')),
          dispatcher.generateTimeout(
              config('wan2.7-image', Vendors.dashscope, tag: 'chat')));
    });

    test('one id under two selections is two descriptors', () {
      final images = served('nano-banana-pro', Vendors.openAIRest,
          tag: 'image', wireProtocol: 'openai-images');
      final chat = served('nano-banana-pro', Vendors.newApiOpenAI,
          tag: 'image', wireProtocol: 'chat-image');
      expect(images.family, ModelFamily.openaiImage);
      expect(chat.family, ModelFamily.other);
      expect(chat.capabilities.imageParams, isEmpty);
      // And the id's own descriptor was not overwritten by either.
      expect(ModelDescriptor.of('nano-banana-pro').family, ModelFamily.other);
      expect(ModelDescriptor.of('nano-banana-pro').capabilities.isImageGenerator,
          isFalse);
    });

    test('the descriptor door agrees with resolveTarget', () {
      final viaDoor = LLMDispatcher.descriptorFor(
        channelType: Vendors.openAIRest,
        modelId: 'my-sora',
        tag: 'video',
      );
      expect(identical(viaDoor, served('my-sora', Vendors.openAIRest, tag: 'video')),
          isTrue);
    });
  });
}
