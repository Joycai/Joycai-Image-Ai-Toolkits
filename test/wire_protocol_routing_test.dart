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
    test('DashScope chat models offer the ①/④ pair, ① first', () {
      expect(
        LLMDispatcher.protocolMenuFor(Vendors.dashscope, 'qwen-max'),
        [WireProtocol.openaiChat, WireProtocol.anthropicChat],
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

    test('the ④ face pin flips streamSupportsTools on an ① vendor', () {
      final dispatcher = LLMDispatcher();
      expect(
          dispatcher.streamSupportsTools(config('qwen-max', Vendors.dashscope)),
          isFalse);
      expect(
          dispatcher.streamSupportsTools(config('qwen-max', Vendors.dashscope,
              wireProtocol: 'anthropic-chat')),
          isTrue);
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

    test('everyone else keeps empty menus (family defaults)', () {
      for (final id in [
        Vendors.openAIRest,
        Vendors.newApiOpenAI,
        Vendors.deepseek,
        Vendors.minimax,
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
