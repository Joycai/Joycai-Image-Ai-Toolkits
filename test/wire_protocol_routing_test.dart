import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the vendor–protocol–model binding introduced by the wire-protocol
/// refactor: per-surface menus, the per-model selection, and — most
/// importantly — that every (vendor, model) combination that existed before
/// the refactor still resolves to the same route.
void main() {
  LLMModelConfig config(String modelId, String channelType,
          {String? wireProtocol}) =>
      LLMModelConfig(
        modelId: modelId,
        channelType: channelType,
        endpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        apiKey: 'k',
        wireProtocol: wireProtocol,
      );

  group('surfaceForModel', () {
    test('classifies by family kind', () {
      expect(LLMDispatcher.surfaceForModel('qwen-max'), Surface.chat);
      expect(LLMDispatcher.surfaceForModel('wan2.7-image'), Surface.imageGen);
      expect(LLMDispatcher.surfaceForModel('wan3.0-video'), Surface.videoJob);
      expect(LLMDispatcher.surfaceForModel('gpt-4o'), Surface.chat);
      expect(LLMDispatcher.surfaceForModel('gpt-image-1'), Surface.imageGen);
      expect(LLMDispatcher.surfaceForModel('sora-2'), Surface.videoJob);
    });
  });

  group('protocolMenuFor', () {
    test('DashScope chat models offer all three faces, compatible first', () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscope, 'qwen-max'),
        [
          WireProtocol.openaiChat,
          WireProtocol.anthropicChat,
          WireProtocol.dashscopeChat,
        ],
      );
    });

    test('the native vendor offers the same three, native first', () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscopeNative, 'qwen-max'),
        [
          WireProtocol.dashscopeChat,
          WireProtocol.openaiChat,
          WireProtocol.anthropicChat,
        ],
      );
    });

    test('the native vendor keeps the same image and video menus', () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscopeNative, 'wan2.7-image'),
        [WireProtocol.dashscopeImagesSync, WireProtocol.dashscopeImagesAsync],
      );
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscopeNative, 'wan3.0-video'),
        [WireProtocol.dashscopeVideo],
      );
    });

    test('wan2.7 image offers sync + async, sync first', () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscope, 'wan2.7-image'),
        [WireProtocol.dashscopeImagesSync, WireProtocol.dashscopeImagesAsync],
      );
    });

    test('qwen-image is sync-only — the async entry is filtered by layer 3',
        () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscope, 'qwen-image-3.0'),
        [WireProtocol.dashscopeImagesSync],
      );
    });

    test('a relay listing qwen-image offers no menu (chat route stands)', () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.openAIRest, 'qwen-image-3.0'),
        isEmpty,
      );
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.newApiOpenAI, 'wan2.7-image'),
        isEmpty,
      );
    });

    test('video is a single fixed route per vendor', () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscope, 'wan3.0-video'),
        [WireProtocol.dashscopeVideo],
      );
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.openAIRest, 'sora-2'),
        isEmpty,
      );
    });

    test('single-face vendors degrade to a single-entry chat menu', () {
      expect(LLMDispatcher.protocolMenuFor(Vendors.anthropicRest, 'claude-x'),
          [WireProtocol.anthropicChat]);
      expect(LLMDispatcher.protocolMenuFor(Vendors.ollama, 'llama3'),
          [WireProtocol.openaiChat]);
      expect(LLMDispatcher.protocolMenuFor(Vendors.officialGoogle, 'gemini-2.5-pro'),
          [WireProtocol.geminiChat]);
    });

    test('xAI image models have a fixed native route, no menu beyond it', () {
      // The menu is only rendered when length > 1; xAI's single entry is a
      // routing fact, not a user choice.
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.xaiApi, 'grok-imagine-image'),
        isEmpty,
      );
    });
  });

  group('isStaleProtocolSelection', () {
    test('null/empty is never stale', () {
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'wan2.7-image', null),
          isFalse);
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'wan2.7-image', ''),
          isFalse);
    });

    test('a valid selection is not stale', () {
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'wan2.7-image', 'dashscope-images-async'),
          isFalse);
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'qwen-max', 'anthropic-chat'),
          isFalse);
    });

    test('the channel changing suppliers strands the selection', () {
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.openAIRest, 'wan2.7-image', 'dashscope-images-async'),
          isTrue);
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.openAIRest, 'qwen-max', 'anthropic-chat'),
          isTrue);
    });

    test('unknown ids (a newer build) and unsupported models are stale', () {
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'qwen-max', 'quantum-chat'),
          isTrue);
      // qwen-image cannot do the async task — a selection naming it is stale.
      expect(
          LLMDispatcher.isStaleProtocolSelection(
              Vendors.dashscope, 'qwen-image-3.0', 'dashscope-images-async'),
          isTrue);
    });
  });

  group('routing stays put for pinned + auto (behavior preservation)', () {
    test('async pin lifts generateTimeout above the sync guard', () {
      final dispatcher = LLMDispatcher();
      final sync = dispatcher.generateTimeout(
          config('wan2.7-image', Vendors.dashscope));
      final async = dispatcher.generateTimeout(config(
          'wan2.7-image', Vendors.dashscope,
          wireProtocol: 'dashscope-images-async'));
      expect(async, greaterThan(sync));
    });

    test('a stale pin does not change the timeout (routes as auto)', () {
      final dispatcher = LLMDispatcher();
      expect(
        dispatcher.generateTimeout(config('wan2.7-image', Vendors.openAIRest,
            wireProtocol: 'dashscope-images-async')),
        dispatcher.generateTimeout(config('wan2.7-image', Vendors.openAIRest)),
      );
    });

    test('every chat face streams tool calls, whichever one is pinned', () {
      final dispatcher = LLMDispatcher();
      // Was ④-only until ① and C2 grew accumulators of their own
      // (`StreamingToolCallAccumulator`), which is why the pin used to flip
      // this answer and no longer does. A `false` here is not a cosmetic
      // regression: `LLMService.request` silently downgrades a tool-bearing
      // request to the synchronous path, where the entire generation has to
      // land inside one deadline instead of resetting a guard per chunk.
      for (final vendor in [Vendors.dashscope, Vendors.dashscopeNative]) {
        expect(dispatcher.streamSupportsTools(config('qwen-max', vendor)),
            isTrue,
            reason: 'auto face on $vendor');
        for (final pin in ['openai-chat', 'anthropic-chat', 'dashscope-chat']) {
          expect(
              dispatcher.streamSupportsTools(
                  config('qwen-max', vendor, wireProtocol: pin)),
              isTrue,
              reason: '$pin pinned on $vendor');
        }
      }
    });
  });

  group('vendor surface declarations', () {
    test('xAI declares its native image/video surfaces via menus', () {
      final xai = Vendors.byId(Vendors.xaiApi);
      expect(xai.imageMenu, [WireProtocol.xaiImages]);
      expect(xai.videoProtocol, WireProtocol.xaiVideos);
    });

    test('DashScope declares all three surfaces on one vendor', () {
      final ds = Vendors.byId(Vendors.dashscope);
      expect(ds.chatMenu.first, WireProtocol.openaiChat);
      expect(ds.videoProtocol, WireProtocol.dashscopeVideo);
      expect(ds.protocolBases.keys, contains(WireProtocol.anthropicChat));
    });

    test('the native vendor is the same supplier led by the native wire', () {
      final native = Vendors.byId(Vendors.dashscopeNative);
      expect(native.family, ProtocolFamily.dashscope);
      expect(native.chatMenu.first, WireProtocol.dashscopeChat);
      expect(native.videoProtocol, WireProtocol.dashscopeVideo);
      // Both generic alternates are served on another base of the same host,
      // so both are derived — a channel storing `…/api/v1` still reaches the
      // ① and ④ faces, and discovery (which only exists on ①) still works.
      expect(native.protocolBases.keys,
          containsAll([WireProtocol.openaiChat, WireProtocol.anthropicChat]));
    });

    test('both MiniMax faces declare the same two native surfaces', () {
      // The chat wire is a property of the channel — the ① face and the ④
      // face are two endpoints the user picks between. Which image and video
      // endpoints MiniMax *has* is not a choice, so both ids declare both,
      // and each protocol derives the base it needs from whichever face the
      // channel stored.
      for (final id in [Vendors.minimax, Vendors.minimaxAnthropic]) {
        final v = Vendors.byId(id);
        expect(v.imageMenu, [WireProtocol.minimaxImages], reason: id);
        expect(v.videoProtocol, WireProtocol.minimaxVideo, reason: id);
      }
      expect(Vendors.byId(Vendors.minimax).family, ProtocolFamily.openai);
      expect(Vendors.byId(Vendors.minimaxAnthropic).family,
          ProtocolFamily.anthropic);
    });

    test('everyone else keeps empty menus (family defaults)', () {
      for (final id in [
        Vendors.openAIRest,
        Vendors.newApiOpenAI,
        Vendors.deepseek,
        Vendors.anthropicRest,
        Vendors.ollama,
      ]) {
        final v = Vendors.byId(id);
        expect(v.chatMenu, isEmpty, reason: id);
        expect(v.imageMenu, isEmpty, reason: id);
        expect(v.videoProtocol, isNull, reason: id);
      }
    });
  });

  group('layer 3 additions', () {
    test('wan3.0 video ids classify as async video-task models', () {
      expect(ModelFamilyClassifier.classify('wan3.0-video'),
          ModelFamily.openaiVideo);
      expect(ModelFamilyClassifier.classify('wan3.0-video-prime'),
          ModelFamily.openaiVideo);
    });

    test('wan2.6-image is parked in the DashScope image family', () {
      expect(ModelFamilyClassifier.classify('wan2.6-image'),
          ModelFamily.dashscopeImage);
    });

    test('existing video ids are untouched by the new rules', () {
      expect(ModelFamilyClassifier.classify('wan2.5-t2v-plus'),
          ModelFamily.openaiVideo);
      expect(ModelFamilyClassifier.classify('wan2.7-image'),
          ModelFamily.dashscopeImage);
    });

    test('async-task support is declared per model, not per family', () {
      expect(
          ModelCapabilities.forModel('wan2.7-image').supportsAsyncImageTask,
          isTrue);
      expect(
          ModelCapabilities.forModel('qwen-image-edit').supportsAsyncImageTask,
          isFalse);
    });

    test('wan3 video exposes the billed audio toggle', () {
      final caps = ModelCapabilities.forModel('wan3.0-video');
      expect(caps.isVideoGenerator, isTrue);
      expect(caps.videoParams.map((p) => p.key), contains('videoAudio'));
    });
  });

  group('dashscopeAnthropicBase', () {
    test('derives the ④ base from any face of the same host', () {
      const want = 'https://dashscope.aliyuncs.com/apps/anthropic/v1';
      for (final input in [
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'https://dashscope.aliyuncs.com/compatible-mode/v1/',
        'https://dashscope.aliyuncs.com',
        'https://dashscope.aliyuncs.com/api/v1',
        'https://dashscope.aliyuncs.com/apps/anthropic',
        want,
      ]) {
        expect(dashscopeAnthropicBase(input), want, reason: input);
      }
    });

    test('keys off the path only — the intl host works unchanged', () {
      expect(
        dashscopeAnthropicBase(
            'https://dashscope-intl.aliyuncs.com/compatible-mode/v1'),
        'https://dashscope-intl.aliyuncs.com/apps/anthropic/v1',
      );
    });

    test('native base derivation still strips every known face', () {
      const want = 'https://dashscope.aliyuncs.com/api/v1';
      for (final input in [
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'https://dashscope.aliyuncs.com/apps/anthropic/v1',
        'https://dashscope.aliyuncs.com/api/v1',
        'https://dashscope.aliyuncs.com',
      ]) {
        expect(dashscopeNativeBase(input), want, reason: input);
      }
    });

    test('the compatible base derives back the other way', () {
      // A natively-configured channel still needs this one: the ① chat
      // alternate lives there, and so does the only `GET /models` DashScope
      // publishes — without it the native vendor's "fetch models" could
      // only ever fail.
      const want = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      for (final input in [
        'https://dashscope.aliyuncs.com/api/v1',
        'https://dashscope.aliyuncs.com/api/v1/',
        'https://dashscope.aliyuncs.com/apps/anthropic/v1',
        'https://dashscope.aliyuncs.com',
        want,
      ]) {
        expect(dashscopeCompatibleBase(input), want, reason: input);
      }
      expect(
        dashscopeCompatibleBase('https://dashscope-intl.aliyuncs.com/api/v1'),
        'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
      );
    });
  });

  group('MiniMax surfaces', () {
    LLMModelConfig mm(String modelId, String channelType,
            {String endpoint = 'https://api.minimaxi.com/anthropic/v1'}) =>
        LLMModelConfig(
          modelId: modelId,
          channelType: channelType,
          endpoint: endpoint,
          apiKey: 'k',
        );

    test('image-01 is its own family; MiniMax-M3 stays chat', () {
      expect(ModelFamilyClassifier.classify('image-01'),
          ModelFamily.minimaxImage);
      expect(ModelFamilyClassifier.classify('image-01-live'),
          ModelFamily.minimaxImage);
      // One letter apart, two surfaces. H3 is the video model; M3 is chat and
      // must not be dragged onto the video route by a loose prefix rule.
      expect(ModelFamilyClassifier.classify('MiniMax-H3'),
          ModelFamily.openaiVideo);
      expect(ModelFamilyClassifier.classify('MiniMax-M3'), ModelFamily.other);
      expect(ModelFamilyClassifier.classify('MiniMax-M2.7-highspeed'),
          ModelFamily.other);
    });

    test('the image surface is reachable from the anthropic-led face', () {
      // The regression this guards: ④'s own answer is "there is no image
      // surface", and the dispatcher used to throw/route to chat on the
      // family alone. A ④ *vendor* can still declare one.
      expect(LLMDispatcher.surfaceForModel('image-01'), Surface.imageGen);
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.minimaxAnthropic, 'image-01'),
        [WireProtocol.minimaxImages],
      );
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.minimax, 'image-01'),
        [WireProtocol.minimaxImages],
      );
      // Single entry means no selector renders, but the route still exists.
      expect(LLMDispatcher.autoProtocolFor(Vendors.minimax, 'image-01'),
          WireProtocol.minimaxImages);
    });

    test('a relay listing image-01 keeps routing it through chat', () {
      // Same rule DashScope's images follow: the native surface is the
      // vendor's declaration, not the model id. A relay serves image-01
      // through its own compatibility layer and would 404 on
      // /v1/image_generation.
      for (final id in [Vendors.openAIRest, Vendors.newApiOpenAI]) {
        expect(LLMDispatcher.protocolMenuFor(id, 'image-01'), isEmpty,
            reason: id);
      }
    });

    test("one vendor's image menu never claims another's model", () {
      // image-01 and qwen-image both classify into a native image family, and
      // both vendors declare a non-empty imageMenu. Before the menus were
      // intersected per family, `imageMenu.isNotEmpty` was the whole test —
      // so a qwen-image typed into a MiniMax channel resolved to MiniMax's
      // endpoint, and vice versa.
      expect(LLMDispatcher.protocolMenuFor(Vendors.minimax, 'qwen-image'),
          isEmpty);
      expect(LLMDispatcher.protocolMenuFor(Vendors.dashscope, 'image-01'),
          isEmpty);
    });

    test('an image model declares no streaming tools on either face', () {
      final dispatcher = LLMDispatcher();
      for (final id in [Vendors.minimax, Vendors.minimaxAnthropic]) {
        expect(dispatcher.streamSupportsTools(mm('image-01', id)), isFalse,
            reason: id);
        expect(dispatcher.streamIsSingleShot(mm('image-01', id)), isTrue,
            reason: id);
      }
      // Chat on the same channels is untouched.
      expect(dispatcher.streamSupportsTools(mm('MiniMax-M3', Vendors.minimax)),
          isTrue);
      expect(
          dispatcher
              .streamSupportsTools(mm('MiniMax-M3', Vendors.minimaxAnthropic)),
          isTrue);
      expect(
          dispatcher.streamIsSingleShot(mm('MiniMax-M3', Vendors.minimax)),
          isFalse);
    });

    test('the sync image surface gets a generation-sized deadline', () {
      // longRunning: one request runs the whole generation upstream, and it
      // is billed before a chat-sized guard would give up on it.
      final dispatcher = LLMDispatcher();
      expect(
        dispatcher.generateTimeout(mm('image-01', Vendors.minimaxAnthropic)),
        greaterThan(
            dispatcher.generateTimeout(mm('MiniMax-M3', Vendors.minimax))),
      );
    });

    test('the video route survives on the anthropic-led face', () {
      expect(LLMDispatcher.surfaceForModel('MiniMax-H3'), Surface.videoJob);
      for (final id in [Vendors.minimax, Vendors.minimaxAnthropic]) {
        expect(LLMDispatcher.protocolMenuFor(id, 'MiniMax-H3'),
            [WireProtocol.minimaxVideo],
            reason: id);
      }
    });

    test('the model picker agrees with the router about ④ video', () {
      // The regression: the picker carried its own copy of "which channels
      // can run a video job" and answered "the Anthropic family cannot".
      // When a ④ vendor declared a native video surface, H3 vanished from the
      // workbench while the route behind it worked — no error, just an empty
      // list. AppState now asks this method instead of re-deriving the rule.
      final dispatcher = LLMDispatcher();
      for (final id in [Vendors.minimax, Vendors.minimaxAnthropic]) {
        expect(dispatcher.canRunVideoJob(mm('MiniMax-H3', id)), isTrue,
            reason: id);
        // A chat id on the same channel must not slip into the picker.
        expect(dispatcher.canRunVideoJob(mm('MiniMax-M3', id)), isFalse,
            reason: id);
      }
      // A ④ vendor with no video surface declared still cannot.
      expect(
          dispatcher.canRunVideoJob(mm('MiniMax-H3', Vendors.anthropicRest)),
          isFalse);
      // Every family that could before still can.
      expect(dispatcher.canRunVideoJob(mm('veo-3.0', Vendors.officialGoogle)),
          isTrue);
      expect(dispatcher.canRunVideoJob(mm('sora-2', Vendors.openAIRest)),
          isTrue);
      expect(
          dispatcher.canRunVideoJob(mm('wan3.0-video', Vendors.dashscopeNative)),
          isTrue);
      expect(dispatcher.canRunVideoJob(mm('gpt-4o', Vendors.openAIRest)),
          isFalse);
      expect(dispatcher.canRunVideoJob(mm('mj_imagine', Vendors.midjourneyProxy)),
          isFalse);
    });
  });

  group('WireProtocol ids', () {
    test('stored ids parse back to their values', () {
      for (final p in WireProtocol.values) {
        expect(WireProtocol.tryParse(p.id), p);
      }
    });

    test('unknown and empty degrade to null, never throw', () {
      expect(WireProtocol.tryParse(null), isNull);
      expect(WireProtocol.tryParse(''), isNull);
      expect(WireProtocol.tryParse('from-a-newer-build'), isNull);
    });
  });
}
