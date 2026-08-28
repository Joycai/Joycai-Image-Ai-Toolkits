import 'llm_types.dart';
import 'model_descriptor.dart';
import 'model_family.dart';
import 'protocols/anthropic_chat_protocol.dart';
import 'protocols/dashscope_chat_protocol.dart';
import 'protocols/dashscope_images_async_protocol.dart';
import 'protocols/dashscope_images_protocol.dart';
import 'protocols/dashscope_video_protocol.dart';
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
  static final _dashscopeChat = DashScopeChatProtocol();
  static final _dashscopeImages = DashScopeImagesProtocol();
  static final _dashscopeImagesAsync = DashScopeImagesAsyncProtocol();
  static final _dashscopeVideo = DashScopeVideoProtocol();
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

  // ---------------------------------------------------------------------------
  // Protocol menus and the per-model selection (`llm_models.wire_protocol`)
  // ---------------------------------------------------------------------------

  /// The surface a model's requests belong to, for menu selection. Video and
  /// image-generation families get their own surfaces; everything else —
  /// chat, multimodal, unknown — is the chat surface.
  static Surface surfaceForModel(String modelId) {
    final family = ModelDescriptor.of(modelId).family;
    if (ModelFamilyClassifier.isVideo(family)) return Surface.videoJob;
    if (ModelFamilyClassifier.isImageGeneration(family)) {
      return Surface.imageGen;
    }
    return Surface.chat;
  }

  /// The protocol menu offered for this (channel type, model id) pair: the
  /// vendor's declared menu for the model's surface, intersected with what
  /// the concrete model supports (layer 3). This is the single source for
  /// both routing below and the model editor's selector — one entry (or
  /// none) means there is no choice and no UI.
  static List<WireProtocol> protocolMenuFor(
      String channelType, String modelId) {
    final vendor = Vendors.byId(channelType);
    final model = ModelDescriptor.of(modelId);
    final surface = surfaceForModel(modelId);
    switch (surface) {
      case Surface.chat:
        return vendor.menuFor(Surface.chat);
      case Surface.imageGen:
        // Only the family the dispatcher actually routes to the vendor's
        // native image surface gets its menu; every other image family rides
        // a fixed route (its own protocol, or chat on a relay) and offers no
        // choice.
        if (model.family != ModelFamily.dashscopeImage) return const [];
        final menu = vendor.menuFor(Surface.imageGen);
        if (!model.capabilities.supportsAsyncImageTask) {
          return menu
              .where((p) => p != WireProtocol.dashscopeImagesAsync)
              .toList();
        }
        return menu;
      case Surface.videoJob:
        // A video model has exactly one route per vendor today.
        return vendor.menuFor(Surface.videoJob);
    }
  }

  /// What "auto" resolves to for this pair — the menu's first entry. Null
  /// when the surface has no vendor menu at all (relay image models riding
  /// chat, families with a single fixed route).
  static WireProtocol? autoProtocolFor(String channelType, String modelId) {
    final menu = protocolMenuFor(channelType, modelId);
    return menu.isEmpty ? null : menu.first;
  }

  /// Whether a stored selection is stale for this pair: non-empty but no
  /// longer valid (unknown id, wrong surface, or off the current vendor's
  /// menu — typically after the channel changed suppliers). Stale values are
  /// silently ignored by routing and surfaced, not blocked, by the UI.
  static bool isStaleProtocolSelection(
      String channelType, String modelId, String? stored) {
    if (stored == null || stored.isEmpty) return false;
    final parsed = WireProtocol.tryParse(stored);
    if (parsed == null) return true;
    return !protocolMenuFor(channelType, modelId).contains(parsed);
  }

  /// The model's explicit, still-valid protocol selection for [surface], or
  /// null for auto. Invalid values (unknown, wrong surface, off the menu)
  /// degrade to auto here — routing never fails on a stale preference.
  WireProtocol? _pinnedProtocol(LLMTarget target, Surface surface) {
    final pinned = WireProtocol.tryParse(target.config.wireProtocol);
    if (pinned == null || pinned.surface != surface) return null;
    final menu =
        protocolMenuFor(target.config.channelType, target.config.modelId);
    return menu.contains(pinned) ? pinned : null;
  }

  /// [target] with its endpoint rewritten for a generic protocol served on
  /// one of this vendor's alternate faces (VendorProfile.protocolBases).
  /// Identity for everything else.
  LLMTarget _faceTarget(LLMTarget target, WireProtocol protocol) {
    final derive = target.vendor.protocolBases[protocol];
    if (derive == null) return target;
    return LLMTarget(
      config: target.config.withEndpoint(derive(target.config.endpoint)),
      vendor: target.vendor,
      model: target.model,
    );
  }

  /// The chat wire serving this target: the model's pinned choice, else the
  /// vendor's chat default (its menu's first entry).
  ///
  /// Only the multi-face families ask — ③ and ④ vendors have a single-entry
  /// menu, so the answer is their family default and the branch never runs.
  WireProtocol _chatFace(LLMTarget target) =>
      _pinnedProtocol(target, Surface.chat) ??
      target.vendor.menuFor(Surface.chat).first;

  /// The implementation behind a chat wire. Every value that can reach here
  /// is one a multi-face vendor declared; anything else degrades to ①, which
  /// is what an unrecognized face on an OpenAI-shaped host would have been
  /// before menus existed.
  ChatProtocol _chatProtocolFor(WireProtocol face) => switch (face) {
        WireProtocol.anthropicChat => _anthropicChat,
        WireProtocol.dashscopeChat => _dashscopeChat,
        _ => _openaiChat,
      };

  /// The image protocol for a DashScope-native image model on a vendor that
  /// declares the surface: the model's pinned choice, else sync.
  ImageGenProtocol _dashscopeImageProtocol(LLMTarget target) =>
      _pinnedProtocol(target, Surface.imageGen) ==
              WireProtocol.dashscopeImagesAsync
          ? _dashscopeImagesAsync
          : _dashscopeImages;

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
  /// The streaming path normally does not use this at all — its guard is per
  /// chunk, and progress resets it — which is why this mostly mattered for
  /// `useStream: false`, and why teaching a protocol to stream tool calls is
  /// the real fix rather than a bigger number here. The exception is a route
  /// [streamIsSingleShot] answers `true` for, where "streaming" is this very
  /// call re-emitted afterwards: there the first-chunk guard borrows this
  /// deadline, because there is nothing else for it to measure.
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
      // The async-task alternate runs submit + the whole poll loop inside one
      // generateImage() call, so this guard must outlive the loop's own
      // 9-minute overall deadline — otherwise the outer timeout fires first
      // and reports "timed out" for a task that is still (billed and)
      // running.
      if (_pinnedProtocol(target, Surface.imageGen) ==
          WireProtocol.dashscopeImagesAsync) {
        return const Duration(minutes: 10);
      }
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
        // DashScope's native image models, on a vendor that declares the
        // surface only. Everywhere else — a relay that lists `qwen-image` —
        // the model keeps falling through to chat below, which is where those
        // relays actually serve it (they answer with images in the chat
        // response, and most expose no /images/generations for it at all).
        // Routing them to an Images API on the strength of the family alone
        // would break channels that work today. Sync vs. async is the model's
        // pinned selection, defaulting to sync.
        if (target.model.family == ModelFamily.dashscopeImage &&
            target.vendor.imageMenu.isNotEmpty) {
          return _dashscopeImageProtocol(target)
              .generateImage(target, history, options: options, logger: logger);
        }

        // Grok Imagine image models: xAI's JSON Images API on native
        // channels; OpenAI-style Images API when served through a relay.
        if (target.model.family == ModelFamily.xaiImage) {
          final protocol =
              target.vendor.imageMenu.contains(WireProtocol.xaiImages)
                  ? _xaiImages
                  : _openaiImages;
          return protocol.generateImage(target, history, options: options, logger: logger);
        }

        // The chat surface itself can be multi-face (DashScope's
        // ④-compatible `/apps/anthropic/v1/messages` and its own
        // `/api/v1/services/aigc/*` beside its ①). The pinned selection
        // decides; the vendor's protocolBases rewrite the endpoint so a
        // generic protocol serving an alternate face stays vendor-blind.
        return _chatGenerate(target, history,
            options: options, tools: tools, logger: logger);

      case ProtocolFamily.dashscope:
        // Native-first DashScope. The image menu is the same one its
        // compatible sibling declares, so an image model takes the same
        // native route by the same pinned selection; everything else is
        // chat, on whichever of the three faces the model pinned.
        if (target.model.family == ModelFamily.dashscopeImage &&
            target.vendor.imageMenu.isNotEmpty) {
          return _dashscopeImageProtocol(target)
              .generateImage(target, history, options: options, logger: logger);
        }
        return _chatGenerate(target, history,
            options: options, tools: tools, logger: logger);
    }
  }

  /// Run one chat request on the face this target resolves to.
  Future<LLMResponse> _chatGenerate(
    LLMTarget target,
    List<LLMMessage> history, {
    Map<String, dynamic>? options,
    List<LLMTool>? tools,
    LLMLogger? logger,
  }) {
    final face = _chatFace(target);
    return _chatProtocolFor(face).generate(_faceTarget(target, face), history,
        options: options, tools: tools, logger: logger);
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
  /// that a family losing or gaining the ability is a visible one-line change
  /// here, not a silent behaviour flip somewhere else. Every chat family
  /// answers `true` today; the branch stays because the answer is a property
  /// of the resolved route, and a new family arrives at `false`.
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
      case ProtocolFamily.dashscope:
        // The ④ face on a multi-face vendor streams with tools exactly like
        // a native ④ channel; neither the ① surface nor DashScope's own does
        // (yet) — both still need a tool-call accumulator. Asked of the
        // resolved face rather than of the family, so teaching one of them
        // to stream tool calls needs no change here.
        return _chatProtocolFor(_chatFace(target)).streamingDeclaresTools;
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
        if (_streamIsSingleShot(target)) {
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
        if (_streamIsSingleShot(target)) {
          logger?.call('Image model does not support streaming; using Images API.', level: 'DEBUG');
          final response = await generate(config, history, options: options, logger: logger);
          yield* _asChunks(response);
          return;
        }
        final face = _chatFace(target);
        yield* _chatProtocolFor(face).generateStream(
            _faceTarget(target, face), history,
            options: options, tools: tools, logger: logger);
        return;

      case ProtocolFamily.dashscope:
        // Same two rules as the ① branch: the native image surface has no
        // streaming form, so its single-shot result is surfaced as chunks;
        // everything else streams on the resolved chat face.
        if (_streamIsSingleShot(target)) {
          logger?.call('Image model does not support streaming; using the DashScope image surface.', level: 'DEBUG');
          final response = await generate(config, history, options: options, logger: logger);
          yield* _asChunks(response);
          return;
        }
        final dashscopeFace = _chatFace(target);
        yield* _chatProtocolFor(dashscopeFace).generateStream(
            _faceTarget(target, dashscopeFace), history,
            options: options, tools: tools, logger: logger);
        return;
    }
  }

  /// Whether [generateStream] on this route is really a single-shot call
  /// re-emitted as chunks, rather than a live stream.
  ///
  /// The image surfaces have no streaming form, so their whole generation
  /// runs inside one awaited `generate()` and the first chunk appears only
  /// once it is finished. Public because the guard wrapped around the stream
  /// has to know: an idle gap sized for "is this connection still alive"
  /// measures nothing here but the generation itself, and firing it abandons
  /// a task that is already billed and still running — see
  /// [LLMService], and [generateTimeout] for the non-streaming twin of the
  /// same rule.
  bool streamIsSingleShot(LLMModelConfig config) =>
      _streamIsSingleShot(resolveTarget(config));

  bool _streamIsSingleShot(LLMTarget target) {
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
      case ProtocolFamily.anthropic:
        return false;
      case ProtocolFamily.gemini:
        return target.model.family == ModelFamily.geminiImagen;
      case ProtocolFamily.openai:
        return target.model.family == ModelFamily.openaiImage ||
            target.model.family == ModelFamily.xaiImage ||
            (target.model.family == ModelFamily.dashscopeImage &&
                target.vendor.imageMenu.isNotEmpty);
      case ProtocolFamily.dashscope:
        return target.model.family == ModelFamily.dashscopeImage &&
            target.vendor.imageMenu.isNotEmpty;
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

      case ProtocolFamily.dashscope:
        // `video-synthesis` + the shared task poller. The vendor declares the
        // protocol exactly as its compatible sibling does, so the check is
        // the declaration rather than the family — a DashScope channel with
        // no video surface declared should say so, not submit blindly.
        if (target.model.family == ModelFamily.openaiVideo &&
            target.vendor.videoProtocol == WireProtocol.dashscopeVideo) {
          return _dashscopeVideo.submit(target, history,
              options: options, logger: logger);
        }
        throw UnsupportedError(
          'The model "${config.modelId}" is not a DashScope video model; '
          'use wan3.0-video / wan3.0-video-prime for video generation.',
        );

      case ProtocolFamily.openai:
        if (target.model.family == ModelFamily.openaiVideo) {
          // Vendors with a native async-video surface replace the Sora-style
          // multipart `/videos` default: xAI's `/videos/generations` JSON,
          // DashScope's `video-synthesis` task flow.
          final protocol = switch (target.vendor.videoProtocol) {
            WireProtocol.xaiVideos => _xaiVideos,
            WireProtocol.dashscopeVideo => _dashscopeVideo,
            _ => _openaiVideos,
          };
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

      case ProtocolFamily.dashscope:
        // Symmetric with the submit above: an operation on this channel can
        // only have come from `video-synthesis`, and its poll already
        // translates DashScope's task states into the Veo-shaped envelope
        // the task executor speaks.
        return _dashscopeVideo.poll(target, operationName, logger: logger);

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

        // Sora-style ids start with `video_` (NewAPI / OpenAI Sora format),
        // which only the ① `/v1/videos` surface emits — so the id itself,
        // not the channel's current wiring, decides where it is polled.
        //
        // Ahead of the vendor switch below on purpose. Tasks outlive the
        // config that started them: a vendor that gains a `videoProtocol`
        // (DashScope did) would otherwise re-route the operations already
        // sitting in the `tasks` table to its native `GET /tasks/{id}`,
        // where a `video_…` id means nothing — every in-flight video from
        // before the upgrade fails permanently.
        if (operationName.startsWith('video_')) {
          return _openaiVideos.poll(target, operationName, logger: logger);
        }

        // Vendors with a native video surface poll it with their own status
        // vocabulary: xAI's `GET /videos/{request_id}`
        // (pending/done/expired/failed), DashScope's `GET /tasks/{task_id}`
        // (PENDING/RUNNING/SUCCEEDED/FAILED/CANCELED/UNKNOWN). Symmetric
        // with the submit routing above — an operation started on this
        // channel can only have come from its own surface.
        switch (target.vendor.videoProtocol) {
          case WireProtocol.xaiVideos:
            return _xaiVideos.poll(target, operationName, logger: logger);
          case WireProtocol.dashscopeVideo:
            return _dashscopeVideo.poll(target, operationName, logger: logger);
          default:
            break;
        }

        // Non-prefixed ids some upstreams emit (e.g. Wanxiang) dispatch by
        // model family instead.
        if (target.model.family == ModelFamily.openaiVideo) {
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
      case ProtocolFamily.dashscope:
        // DashScope publishes no listing on its native surface; the only
        // `GET /models` it serves is on the compatible face of the same host,
        // under the same key. Rewriting the base is what lets a native
        // channel still populate its model list — the alternative was a
        // vendor whose "fetch models" button could only ever fail.
        return _openaiDiscovery
            .fetchModels(_faceTarget(target, WireProtocol.openaiChat));
    }
  }
}
