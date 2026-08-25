import 'llm_types.dart';
import 'model_descriptor.dart';
import 'model_family.dart';
import 'protocols/anthropic_chat_protocol.dart';
import 'protocols/dashscope_images_protocol.dart';
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
/// Options key: how much output the caller expects, for sizing the
/// non-streaming deadline **only**.
///
/// Deliberately not `maxTokens`. That one is sent on the wire, and raising it
/// to inform the deadline would change what the request asks for — on ① and
/// ③, which send no cap today, it would newly impose one and 400 against any
/// model whose ceiling is lower. This key changes no payload; it only stops
/// [LLMDispatcher.generateTimeout] guessing when the caller already knows.
const String expectedOutputTokensKey = 'expectedOutputTokens';

class LLMDispatcher {
  // Layer-1 protocol implementations (stateless).
  static final _openaiChat = OpenAIChatProtocol();
  static final _openaiImages = OpenAIImagesProtocol();
  static final _openaiVideos = OpenAIVideosProtocol();
  static final _xaiImages = XaiImagesProtocol();
  static final _dashscopeImages = DashScopeImagesProtocol();
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

  /// Whether [discoverModels] actually reaches the network for this channel —
  /// i.e. whether its outcome says anything about connectivity. Midjourney's
  /// discovery returns a built-in catalog without a request, so a probe that
  /// trusted it would report success against any URL.
  bool discoveryUsesNetwork(LLMModelConfig config) =>
      resolveTarget(config).vendor.family != ProtocolFamily.midjourney;

  /// Assumed floor on how fast a model emits output tokens, for sizing the
  /// non-streaming deadline.
  ///
  /// Deliberately pessimistic. Waiting out a slow endpoint costs patience;
  /// giving up early throws away a generation that has already been billed
  /// and cannot be un-run.
  static const int _assumedOutputTokensPerSecond = 25;

  /// Allowance for everything in a non-streaming request that is not
  /// generation: upload, queueing at a relay, and prefill of a full context
  /// window.
  static const Duration _nonGenerationAllowance = Duration(seconds: 60);

  /// Ceiling, so a misconfigured output cap cannot produce an hour-long wait.
  static const Duration _maxChatDeadline = Duration(minutes: 10);

  /// How long a synchronous [generate] may run before the caller times it
  /// out.
  ///
  /// **Scales with the output cap**, because on this path nothing arrives
  /// until the last token: the deadline has to outlive the entire
  /// generation, and "how long is the entire generation" is a function of
  /// how much output was asked for. The flat 120 s this used to return was
  /// unreachable for any answer worth having — a Prompt Assistant
  /// `submit_prompt` runs 6–7 K tokens, which no endpoint finishes in two
  /// minutes, so *every* delivery timed out while the model was still
  /// writing it (docs/plans/2026-08-assistant-timeout.md).
  ///
  /// The floor stays at the historical 120 s so short calls are unaffected.
  ///
  /// The streaming path does not use this at all — its guard is per chunk,
  /// and progress resets it — which is why this only ever mattered for
  /// `useStream: false`, and why teaching a protocol to stream tool calls
  /// is the real fix rather than a bigger number here.
  ///
  /// Midjourney is the outlier that predates all of it: its generate()
  /// *contains* the whole submit → poll → download cycle (up to 10 minutes,
  /// see [MidjourneyProtocol]), so any guard sized for a chat completion
  /// would fail every non-streaming Midjourney call.
  Duration generateTimeout(LLMModelConfig config,
      {Map<String, dynamic>? options}) {
    final target = resolveTarget(config);
    if (target.vendor.family == ProtocolFamily.midjourney) {
      return const Duration(minutes: 11);
    }
    // Routes whose single request runs the generation to completion upstream
    // (DashScope's synchronous image surface). Declared per model in layer 3
    // rather than derived from the family, because the same family also
    // serves chat models that must keep the short guard.
    //
    // Kept separate from the Midjourney rule above rather than folded into
    // it: Midjourney's exemption belongs to the *protocol* — its generate()
    // contains the poll loop whatever model id the channel names — and
    // routing it through a model capability would quietly drop the exemption
    // for a Midjourney channel whose model id classifies as something else.
    if (target.model.capabilities.longRunning) {
      return const Duration(minutes: 5);
    }

    final deadline = _nonGenerationAllowance +
        Duration(
            seconds: _outputCap(target, options) ~/ _assumedOutputTokensPerSecond);
    if (deadline < const Duration(seconds: 120)) return const Duration(seconds: 120);
    if (deadline > _maxChatDeadline) return _maxChatDeadline;
    return deadline;
  }

  /// How much output to size the deadline against, best source first.
  ///
  /// 1. **`maxTokens`** — the cap the request will actually carry. A fact,
  ///    so nothing beats it.
  /// 2. **[expectedOutputTokensKey]** — what the caller expects to *receive*.
  ///    Reaches no payload; it exists because ① and ③ send no cap at all, so
  ///    the alternative is a guess, and an agent that knows it is asking for
  ///    a 6-7 K-token document knows better than the guess does.
  /// 3. **A family default.** ④ has no server-side default and the adapter
  ///    substitutes [anthropicDefaultMaxTokens], so that number is a fact
  ///    about the request being sent. ① and ③ leave the field off and let the
  ///    host decide, which is not knowable here — 4096 stands in, low enough
  ///    that the floor usually wins and short calls keep the old behaviour.
  int _outputCap(LLMTarget target, Map<String, dynamic>? options) {
    final requested = requestedMaxTokens(options);
    if (requested != null) return requested;

    final expected = options?[expectedOutputTokensKey];
    if (expected is num && expected >= 1) return expected.toInt();

    return target.vendor.family == ProtocolFamily.anthropic
        ? anthropicDefaultMaxTokens
        : 4096;
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
        // DashScope's native image models, on a DashScope channel only.
        // Everywhere else — a relay that lists `qwen-image` — the model keeps
        // falling through to chat below, which is where those relays actually
        // serve it (they answer with images in the chat response, and most
        // expose no /images/generations for it at all). Routing them to an
        // Images API on the strength of the family alone would break channels
        // that work today.
        if (target.model.family == ModelFamily.dashscopeImage &&
            target.vendor.usesDashScopeNativeImages) {
          return _dashscopeImages.generateImage(target, history, options: options, logger: logger);
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

  /// Whether this route's streaming surface declares client tools, i.e.
  /// whether a tool-bearing request may stream instead of falling back to
  /// [generate].
  ///
  /// The routing question `LLMService` asks before choosing a path, kept here
  /// with every other routing branch rather than derived from the protocol
  /// object at the call site. Written per family rather than as a lookup so
  /// that teaching ① or ③ to stream tool calls is a visible one-line change
  /// here, not a silent behaviour flip somewhere else.
  bool streamSupportsTools(LLMModelConfig config) {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.anthropic:
        return _anthropicChat.streamingDeclaresTools;
      case ProtocolFamily.gemini:
        // Imagen and Veo have no tools and no streaming surface of their own;
        // the chat route is the only one this question can be about.
        return target.model.family == ModelFamily.geminiImagen
            ? false
            : _geminiChat.streamingDeclaresTools;
      case ProtocolFamily.openai:
      case ProtocolFamily.midjourney:
        return false;
    }
  }

  Stream<LLMResponseChunk> generateStream(
    LLMModelConfig config,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) async* {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
        yield* _midjourney.generateStream(target, history, options: options, logger: logger);
        return;

      case ProtocolFamily.anthropic:
        yield* _anthropicChat.generateStream(target, history,
            options: options, tools: tools, logger: logger);
        return;

      case ProtocolFamily.gemini:
        // Imagen has no streaming surface — run the single-shot predict call
        // and emit its result as chunks.
        if (target.model.family == ModelFamily.geminiImagen) {
          final response = await _imagen.generateImage(target, history, options: options, logger: logger);
          yield* _asChunks(response);
          return;
        }
        yield* _geminiChat.generateStream(target, history,
            options: options, tools: tools, logger: logger);
        return;

      case ProtocolFamily.openai:
        // The Images APIs do not stream — fall back to a single-shot call
        // and surface the result as chunks.
        if (target.model.family == ModelFamily.openaiImage ||
            target.model.family == ModelFamily.xaiImage ||
            (target.model.family == ModelFamily.dashscopeImage &&
                target.vendor.usesDashScopeNativeImages)) {
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

        final isSimulation = options?['simulation'] == true || target.model.isMockModel;
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
        // Translated into the same Veo-shaped envelope every other family's
        // poll returns — the only caller (the videoGenerate executor) speaks
        // that envelope, and this used to be the one branch handing back the
        // raw /mj/task JSON instead. Midjourney models classify as an image
        // family, so the branch is defensive rather than routine; all the
        // more reason for it to honor the contract when it does fire.
        final mjTask = await _midjourney.fetchTaskStatus(target, operationName);
        final mjStatus = mjTask['status']?.toString() ?? '';
        if (mjStatus == 'FAILURE') {
          throw LLMApiException(
              'Midjourney task $operationName failed: ${mjTask['failReason'] ?? mjTask}');
        }
        if (mjStatus == 'SUCCESS') {
          return {
            'name': operationName,
            'done': true,
            'response': {
              'generateVideoResponse': {
                'generatedSamples': [
                  {
                    'video': {'uri': mjTask['imageUrl']?.toString() ?? ''},
                  }
                ],
              },
            },
          };
        }
        return {
          'name': operationName,
          'done': false,
          'progress': mjTask['progress'] ?? 0,
          'status': mjStatus,
        };

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
