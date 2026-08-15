import 'llm_types.dart';
import 'model_descriptor.dart';
import 'model_family.dart';
import 'protocols/anthropic_chat_protocol.dart';
import 'protocols/gemini_chat_protocol.dart';
import 'protocols/gemini_imagen_protocol.dart';
import 'protocols/gemini_veo_protocol.dart';
import 'protocols/midjourney_protocol.dart';
import 'protocols/openai_chat_protocol.dart';
import 'protocols/openai_images_protocol.dart';
import 'protocols/openai_videos_protocol.dart';
import 'protocols/protocol.dart';
import 'protocols/xai_images_protocol.dart';
import 'protocols/xai_videos_protocol.dart';
import 'vendors/vendors.dart';

/// Composes the three layers into one request path:
///
/// 1. **Vendor** (layer 2) — resolved from the channel's stored type
///    ([LLMModelConfig.channelType]) via [Vendors.byId]. Supplies auth and
///    the protocol family.
/// 2. **Model** (layer 3) — resolved from the model id via
///    [ModelDescriptor.of]. Supplies capabilities and family classification.
/// 3. **Protocol** (layer 1) — chosen here, from vendor family + model
///    family, and handed a fully-resolved [LLMTarget].
///
/// Every routing rule that used to live as scattered `if`s inside the old
/// provider classes is written out below, once. Protocols themselves contain
/// no routing.
class LLMDispatcher {
  // Layer-1 protocol implementations (stateless).
  static final _openaiChat = OpenAIChatProtocol();
  static final _openaiImages = OpenAIImagesProtocol();
  static final _openaiVideos = OpenAIVideosProtocol();
  static final _xaiImages = XaiImagesProtocol();
  static final _xaiVideos = XaiVideosProtocol();
  static final _geminiChat = GeminiChatProtocol();
  static final _imagen = GeminiImagenProtocol();
  static final _veo = GeminiVeoProtocol();
  static final _midjourney = MidjourneyProtocol();
  static final _anthropicChat = AnthropicChatProtocol();

  static final _openaiDiscovery = OpenAIDiscoveryProtocol();
  static final _geminiDiscovery = GeminiDiscoveryProtocol();
  static final _midjourneyDiscovery = MidjourneyDiscoveryProtocol();
  static final _anthropicDiscovery = AnthropicDiscoveryProtocol();

  /// Resolve the (vendor, model) pair for a request.
  LLMTarget resolveTarget(LLMModelConfig config) => LLMTarget(
        config: config,
        vendor: Vendors.byId(config.channelType),
        model: ModelDescriptor.of(config.modelId),
      );

  /// How long a synchronous [generate] may run before the caller times it
  /// out.
  ///
  /// Midjourney is the outlier: its generate() *contains* the whole
  /// submit → poll → download cycle (up to 10 minutes, see
  /// [MidjourneyProtocol]), so the 120 s guard that fits a single chat
  /// completion would fail every non-streaming Midjourney call at exactly
  /// 120 s. The streaming path is unaffected — progress chunks reset the
  /// caller's timeout — which is why this only ever mattered for
  /// `useStream: false`.
  Duration generateTimeout(LLMModelConfig config) {
    final target = resolveTarget(config);
    return target.vendor.family == ProtocolFamily.midjourney
        ? const Duration(minutes: 11)
        : const Duration(seconds: 120);
  }

  // ---------------------------------------------------------------------------
  // Synchronous generation
  // ---------------------------------------------------------------------------

  Future<LLMResponse> generate(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
        return _midjourney.generate(target, history, options: options, tools: tools, logger: logger);

      case ProtocolFamily.anthropic:
        // One surface for everything ④ does — no image or video sibling to
        // route around, unlike ① and ③.
        return _anthropicChat.generate(target, history, options: options, tools: tools, logger: logger);

      case ProtocolFamily.gemini:
        // Imagen uses the dedicated `:predict` surface, not `:generateContent`.
        if (target.model.family == ModelFamily.geminiImagen) {
          return _imagen.generateImage(target, history, options: options, logger: logger);
        }
        return _geminiChat.generate(target, history, options: options, tools: tools, logger: logger);

      case ProtocolFamily.openai:
        // Native OpenAI image models use the dedicated Images API, not chat.
        if (target.model.family == ModelFamily.openaiImage) {
          return _openaiImages.generateImage(target, history, options: options, logger: logger);
        }
        // Grok Imagine image models: xAI's JSON Images API on native
        // channels; OpenAI-style Images API when served through a relay.
        if (target.model.family == ModelFamily.xaiImage) {
          final protocol = target.vendor.usesXaiNativeSurfaces ? _xaiImages : _openaiImages;
          return protocol.generateImage(target, history, options: options, logger: logger);
        }
        return _openaiChat.generate(target, history, options: options, tools: tools, logger: logger);
    }
  }

  // ---------------------------------------------------------------------------
  // Streaming generation
  // ---------------------------------------------------------------------------

  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async* {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
        yield* _midjourney.generateStream(target, history, options: options, logger: logger);
        return;

      case ProtocolFamily.anthropic:
        yield* _anthropicChat.generateStream(target, history, options: options, logger: logger);
        return;

      case ProtocolFamily.gemini:
        // Imagen has no streaming surface — run the single-shot predict call
        // and emit its result as chunks.
        if (target.model.family == ModelFamily.geminiImagen) {
          final response = await _imagen.generateImage(target, history, options: options, logger: logger);
          yield* _asChunks(response);
          return;
        }
        yield* _geminiChat.generateStream(target, history, options: options, logger: logger);
        return;

      case ProtocolFamily.openai:
        // The Images APIs do not stream — fall back to a single-shot call
        // and surface the result as chunks.
        if (target.model.family == ModelFamily.openaiImage ||
            target.model.family == ModelFamily.xaiImage) {
          logger?.call('Image model does not support streaming; using Images API.', level: 'DEBUG');
          final response = await generate(config, history, options: options, logger: logger);
          yield* _asChunks(response);
          return;
        }
        yield* _openaiChat.generateStream(target, history, options: options, logger: logger);
        return;
    }
  }

  /// Surface a single-shot [response] through the chunk protocol.
  Stream<LLMResponseChunk> _asChunks(LLMResponse response) async* {
    if (response.text.isNotEmpty) {
      yield LLMResponseChunk(textPart: response.text);
    }
    for (final img in response.generatedImages) {
      yield LLMResponseChunk(imagePart: img);
    }
    yield LLMResponseChunk(metadata: response.metadata, isDone: true);
  }

  // ---------------------------------------------------------------------------
  // Long-running operations (video jobs)
  // ---------------------------------------------------------------------------

  Future<String> startLongRunning(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    LLMLogger? logger,
  }) async {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
        throw UnsupportedError(
          'Midjourney generation runs inside generate()/generateStream(); '
          'long-running operations are not used by this protocol.',
        );

      case ProtocolFamily.anthropic:
        throw UnsupportedError(
          'The Anthropic Messages API has no image or video generation '
          'surface; "${config.modelId}" cannot run a long-running operation.',
        );

      case ProtocolFamily.gemini:
        // Veo via :predictLongRunning.
        return _veo.submit(target, history, options: options, logger: logger);

      case ProtocolFamily.openai:
        if (target.model.family == ModelFamily.openaiVideo) {
          // xAI native channels use their own async video surface
          // (`/videos/generations` JSON), not the Sora-style multipart
          // `/videos`.
          final protocol = target.vendor.usesXaiNativeSurfaces ? _xaiVideos : _openaiVideos;
          return protocol.submit(target, history, options: options, logger: logger);
        }

        final isSimulation = options?['simulation'] == true || config.modelId.startsWith('mock-');
        if (isSimulation) {
          logger?.call('Simulating long-running operation for OpenAI-style model: ${config.modelId}', level: 'INFO');
          return 'openai_lro_sim_${DateTime.now().millisecondsSinceEpoch}';
        }

        throw UnsupportedError(
          'The model "${config.modelId}" on the OpenAI protocol family does not support long-running operations. '
          'Use a sora-* / grok-imagine-* / wan2.5-* / kling-* model for video generation.'
        );
    }
  }

  Future<Map<String, dynamic>> checkOperation(
    LLMModelConfig config,
    String operationName, {
    LLMLogger? logger,
  }) async {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
        return _midjourney.fetchTaskStatus(target, operationName);

      case ProtocolFamily.anthropic:
        throw UnsupportedError(
          'Operation "$operationName" cannot belong to an Anthropic channel — '
          'the family has no long-running surface to have started it.',
        );

      case ProtocolFamily.gemini:
        return _veo.poll(target, operationName, logger: logger);

      case ProtocolFamily.openai:
        if (operationName.startsWith('openai_lro_sim_')) {
          // Simulate a completion. The TaskQueueService handles polling.
          return {
            'name': operationName,
            'done': true,
            'response': {
              'generateVideoResponse': {
                'generatedSamples': [
                  {
                    'video': {
                      'uri': 'https://storage.googleapis.com/tf-js-examples/webcam-transfer-learning/video/cat.mp4'
                    }
                  }
                ]
              }
            }
          };
        }

        // xAI native channels poll `GET /videos/{request_id}` with xAI's own
        // status vocabulary (pending / done / expired / failed).
        if (target.vendor.usesXaiNativeSurfaces) {
          return _xaiVideos.poll(target, operationName, logger: logger);
        }

        // Sora-style video task ids start with `video_` (NewAPI / OpenAI Sora
        // format). Also dispatch by model family for non-prefixed ids that
        // some upstreams emit (e.g. Wanxiang).
        if (target.model.family == ModelFamily.openaiVideo || operationName.startsWith('video_')) {
          return _openaiVideos.poll(target, operationName, logger: logger);
        }

        throw UnsupportedError('Operation "$operationName" is not recognized by the OpenAI protocol family.');
    }
  }

  // ---------------------------------------------------------------------------
  // Model discovery
  // ---------------------------------------------------------------------------

  Future<List<DiscoveredModel>> discoverModels(LLMModelConfig config) {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
        return _midjourneyDiscovery.fetchModels(target);
      case ProtocolFamily.anthropic:
        return _anthropicDiscovery.fetchModels(target);
      case ProtocolFamily.gemini:
        return _geminiDiscovery.fetchModels(target);
      case ProtocolFamily.openai:
        return _openaiDiscovery.fetchModels(target);
    }
  }
}
