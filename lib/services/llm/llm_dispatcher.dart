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
import 'protocols/minimax_h3_base_video_protocol.dart';
import 'protocols/minimax_images_protocol.dart';
import 'protocols/minimax_video_protocol.dart';
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

/// What [LLMDispatcher.startLongRunning] hands back: the upstream operation id
/// together with the wire surface that issued it.
///
/// The surface is the operation's provenance. Tasks outlive the config that
/// started them — the channel can be re-pointed at another vendor while the
/// job is still running — so callers persist [surfaceId] next to the id and
/// pass it back to [LLMDispatcher.checkOperation] / [cancelOperation], which
/// then poll the surface the job actually came from instead of re-deriving a
/// route from the channel's *current* wiring. [surface] is null only for the
/// simulated path, which never leaves the process.
class LLMOperationTicket {
  final String name;
  final WireProtocol? surface;

  /// The stable string form ([WireProtocol.id]) for persistence. Parsed back
  /// leniently ([WireProtocol.tryParse]) so a row written by a newer build
  /// degrades to the legacy routing instead of failing.
  String? get surfaceId => surface?.id;

  const LLMOperationTicket(this.name, this.surface);
}

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
  static final _minimaxImages = MiniMaxImagesProtocol();
  static final _minimaxVideo = MiniMaxVideoProtocol();
  static final _minimaxH3BaseVideo = MiniMaxH3BaseVideoProtocol();
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
        // Only the families the dispatcher actually routes to a vendor's
        // native image surface get its menu; every other image family rides
        // a fixed route (its own protocol, or chat on a relay) and offers no
        // choice.
        //
        // The menu is also intersected with what this vendor serves, not just
        // with what the model is: an id classifies by its own name, so a
        // `qwen-image` typed into a MiniMax channel would otherwise be handed
        // that vendor's menu and routed at an endpoint that has never heard
        // of it.
        final menu = vendor
            .menuFor(Surface.imageGen)
            .where((p) => _imageProtocolsFor(model.family).contains(p))
            .toList();
        if (menu.isEmpty) return const [];
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

  /// The native image protocols that can serve [family] — the intersection
  /// term that keeps a vendor's image menu from claiming another vendor's
  /// model.
  ///
  /// Empty for every family with no native image surface of its own
  /// (`gpt-image-*`, nanoBanana, Midjourney): those ride a fixed route the
  /// menus never describe.
  static List<WireProtocol> _imageProtocolsFor(ModelFamily family) {
    switch (family) {
      case ModelFamily.dashscopeImage:
        return const [
          WireProtocol.dashscopeImagesSync,
          WireProtocol.dashscopeImagesAsync,
        ];
      case ModelFamily.minimaxImage:
        return const [WireProtocol.minimaxImages];
      default:
        return const [];
    }
  }

  /// Whether this target's model is an image family the *resolved vendor*
  /// actually serves natively — the guard every image-routing branch below
  /// shares.
  ///
  /// A relay listing `qwen-image` or `image-01` declares no such menu and so
  /// keeps falling through to chat, which is where those relays really serve
  /// them (they answer with images in the chat response). Routing on the
  /// model family alone would break channels that work today.
  bool _hasNativeImageRoute(LLMTarget target) => target.vendor.imageMenu
      .any((p) => _imageProtocolsFor(target.model.family).contains(p));

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

  /// The native image protocol serving this target — the model's pinned
  /// choice, else the vendor's first entry for that model's family.
  ///
  /// Only ever called behind [_hasNativeImageRoute], so the fallback is
  /// unreachable in practice; it stays because "no native route" and "the
  /// wrong native route" must not be the same bug.
  ImageGenProtocol _nativeImageProtocol(LLMTarget target) {
    final pinned = _pinnedProtocol(target, Surface.imageGen);
    final face = pinned ??
        protocolMenuFor(target.config.channelType, target.config.modelId)
            .firstOrNull;
    switch (face) {
      case WireProtocol.dashscopeImagesAsync:
        return _dashscopeImagesAsync;
      case WireProtocol.minimaxImages:
        return _minimaxImages;
      default:
        return _dashscopeImages;
    }
  }

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
        // ④ itself has no image surface — but a ④ *vendor* may. MiniMax
        // serves `/v1/image_generation` on the same host and key as its
        // `/anthropic/v1` chat, so the check is the vendor's declaration
        // rather than the family, exactly as on ① below.
        if (_hasNativeImageRoute(target)) {
          return _nativeImageProtocol(target)
              .generateImage(target, history, options: options, logger: logger);
        }
        // Through [_chatGenerate] rather than straight at the protocol, so a
        // ④ vendor whose chat face sits at a derived path gets its endpoint
        // rewritten like every other family's. Identical routing for every ④
        // vendor that declares no `protocolBases` — the menu of a ④ vendor
        // has one entry, so the resolved face is always [_anthropicChat].
        return _chatGenerate(target, history,
            options: options, tools: tools, logger: logger);

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
        // The vendor-native image surfaces — DashScope's and MiniMax's — on
        // a vendor that declares the matching one. Everywhere else (a relay
        // that lists `qwen-image` or `image-01`) the model keeps falling
        // through to chat below, which is where those relays actually serve
        // it: they answer with images in the chat response, and most expose
        // no image endpoint for it at all. Routing on the strength of the
        // model family alone would break channels that work today. Which
        // protocol, when a vendor offers more than one, is the model's pinned
        // selection — see [_nativeImageProtocol].
        if (_hasNativeImageRoute(target)) {
          return _nativeImageProtocol(target)
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
        if (_hasNativeImageRoute(target)) {
          return _nativeImageProtocol(target)
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
        // An image model on a ④ vendor has no tools and no streaming surface
        // of its own; the chat route is the only one this question is about.
        return _hasNativeImageRoute(target)
            ? false
            : _anthropicChat.streamingDeclaresTools;
      case ProtocolFamily.gemini:
        // Imagen and Veo have no tools and no streaming surface of their own;
        // the chat route is the only one this question can be about.
        return target.model.family == ModelFamily.geminiImagen
            ? false
            : _geminiChat.streamingDeclaresTools;
      case ProtocolFamily.openai:
      case ProtocolFamily.dashscope:
        // Asked of the resolved face rather than of the family, so a face
        // gaining or losing the ability needs no change here. All four chat
        // wires answer true today — each has its own tool-call accumulator
        // — while an image model routed off chat entirely has no tools to
        // declare.
        if (_hasNativeImageRoute(target)) return false;
        return _chatProtocolFor(_chatFace(target)).streamingDeclaresTools;
      case ProtocolFamily.midjourney:
        return false;
    }
  }

  /// Whether a family's chat wire consumes [LLMModelConfig.reasoningEffort].
  ///
  /// The model editor shows the reasoning-intensity control only where
  /// turning the knob changes the request — a knob whose only effect is
  /// nothing is worse than no knob. The answer lives here, with every other
  /// capability query the UI consults (`streamSupportsTools`,
  /// `protocolMenuFor`), because a copy of it in the editor is a silent
  /// failure the day a family gains the ability: C2 read
  /// `effectiveReasoningEffort` to drive `enable_thinking` from the day it
  /// shipped, while the editor's own two-family gate kept the control hidden
  /// on every dashscope-native channel — thinking could never be turned off
  /// there, with nothing anywhere reporting why.
  static bool chatConsumesReasoningEffort(ProtocolFamily family) {
    switch (family) {
      case ProtocolFamily.openai: // reasoning_effort
      case ProtocolFamily.anthropic: // thinking budget tiers
      case ProtocolFamily.dashscope: // enable_thinking / thinking_budget
        return true;
      case ProtocolFamily.gemini:
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
        // A ④ vendor's native image surface has no streaming form — run the
        // single-shot call and emit its result as chunks.
        if (_streamIsSingleShot(target)) {
          logger?.call(
              'Image model does not support streaming; using the vendor image surface.',
              level: 'DEBUG');
          final response =
              await generate(config, history, options: options, logger: logger);
          yield* _asChunks(response);
          return;
        }
        final anthropicFace = _chatFace(target);
        yield* _chatProtocolFor(anthropicFace).generateStream(
            _faceTarget(target, anthropicFace), history,
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
        return false;
      case ProtocolFamily.anthropic:
        return _hasNativeImageRoute(target);
      case ProtocolFamily.gemini:
        return target.model.family == ModelFamily.geminiImagen;
      case ProtocolFamily.openai:
        return target.model.family == ModelFamily.openaiImage ||
            target.model.family == ModelFamily.xaiImage ||
            _hasNativeImageRoute(target);
      case ProtocolFamily.dashscope:
        return _hasNativeImageRoute(target);
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

  Future<LLMOperationTicket> startLongRunning(
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
        // Same reasoning as the image branch in generate(): the *protocol*
        // has no video surface, but the vendor serving it may. MiniMax's
        // `/v2/video_generation` is on the same host and key as its
        // `/anthropic/v1` chat. Resolved through the shared declaration
        // lookup rather than naming one protocol, so a second ④ vendor with
        // a video surface needs no change here — and so this branch cannot
        // disagree with [canRunVideoJob].
        final nativeVideo = _nativeVideoProtocol(target.vendor.videoProtocol);
        if (target.model.family == ModelFamily.openaiVideo &&
            nativeVideo != null) {
          return LLMOperationTicket(
            await nativeVideo.submit(target, history,
                options: options, logger: logger),
            target.vendor.videoProtocol,
          );
        }
        throw UnsupportedError(
          'The Anthropic Messages API has no image or video generation '
          'surface, and this channel declares no vendor-native one; '
          '"${config.modelId}" cannot run a long-running operation.',
        );

      case ProtocolFamily.gemini:
        // Veo via :predictLongRunning.
        return LLMOperationTicket(
          await _veo.submit(target, history, options: options, logger: logger),
          WireProtocol.geminiVeo,
        );

      case ProtocolFamily.dashscope:
        // `video-synthesis` + the shared task poller. The vendor declares the
        // protocol exactly as its compatible sibling does, so the check is
        // the declaration rather than the family — a DashScope channel with
        // no video surface declared should say so, not submit blindly.
        if (target.model.family == ModelFamily.openaiVideo &&
            target.vendor.videoProtocol == WireProtocol.dashscopeVideo) {
          return LLMOperationTicket(
            await _dashscopeVideo.submit(target, history,
                options: options, logger: logger),
            WireProtocol.dashscopeVideo,
          );
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
          final declared = _nativeVideoProtocol(target.vendor.videoProtocol);
          final protocol = declared ?? _openaiVideos;
          return LLMOperationTicket(
            await protocol.submit(target, history,
                options: options, logger: logger),
            declared != null
                ? target.vendor.videoProtocol
                : WireProtocol.openaiVideos,
          );
        }

        final isSimulation = options?['simulation'] == true || target.model.isMockModel;
        if (isSimulation) {
          logger?.call('Simulating long-running operation for OpenAI-style model: ${config.modelId}', level: 'INFO');
          // No wire surface issued this id; a null surface routes its polls
          // through the legacy family switch, whose sim check answers them.
          return LLMOperationTicket(
              'openai_lro_sim_${DateTime.now().millisecondsSinceEpoch}', null);
        }

        throw UnsupportedError(
          'The model "${config.modelId}" on the OpenAI protocol family does not support long-running operations. '
          'Use a sora-* / grok-imagine-* / wan2.5-* / kling-* model for video generation.'
        );
    }
  }

  /// Polls a long-running operation.
  ///
  /// [surfaceId] is the persisted provenance from the [LLMOperationTicket]
  /// that started the job. When it names a video surface, the poll goes
  /// straight there — the channel's current family, vendor declaration and
  /// id shape are all ignored, because the record of where the job was
  /// submitted outranks every heuristic about where it *would* be submitted
  /// today. Absent or unrecognized (a pre-v38 task row, the simulated path,
  /// a row written by a newer build), routing falls back to the family
  /// switch below with its id-prefix guards.
  Future<Map<String, dynamic>> checkOperation(
    LLMModelConfig config,
    String operationName, {
    String? surfaceId,
    LLMLogger? logger,
  }) async {
    final target = resolveTarget(config);
    final pinned = _videoJobProtocolFor(WireProtocol.tryParse(surfaceId));
    if (pinned != null) {
      return pinned.poll(target, operationName, logger: logger);
    }
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
        // The id decides ahead of the vendor's declaration, same rule (and
        // comment) as the ① branch below: tasks outlive the config that
        // started them, and a channel re-pointed at a ④ vendor mid-poll must
        // not hand a Sora-style id to MiniMax's `/v2` query, where it means
        // nothing and the in-flight task fails permanently.
        if (operationName.startsWith('video_')) {
          return _openaiVideos.poll(target, operationName, logger: logger);
        }
        // Symmetric with the submit above: an operation on this channel can
        // only have come from the vendor-native surface it declares.
        final nativeVideo = _nativeVideoProtocol(target.vendor.videoProtocol);
        if (nativeVideo != null) {
          return nativeVideo.poll(target, operationName, logger: logger);
        }
        throw UnsupportedError(
          'Operation "$operationName" cannot belong to this Anthropic channel '
          '— neither the family nor this vendor has a long-running surface to '
          'have started it.',
        );

      case ProtocolFamily.gemini:
        return _veo.poll(target, operationName, logger: logger);

      case ProtocolFamily.dashscope:
        // Same in-flight guard as the ① and ④ branches — a `video_…` id was
        // issued by the `/v1/videos` surface, never by `video-synthesis`,
        // whatever the channel's wiring says today.
        if (operationName.startsWith('video_')) {
          return _openaiVideos.poll(target, operationName, logger: logger);
        }
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
        // (Tasks submitted since the ticket carries a surface never reach
        // this switch; the prefix guards here and in the ④/C2 branches keep
        // rows persisted before that — and any caller without a surface —
        // polling correctly.)
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
        final nativeVideo = _nativeVideoProtocol(target.vendor.videoProtocol);
        if (nativeVideo != null) {
          return nativeVideo.poll(target, operationName, logger: logger);
        }

        // Non-prefixed ids some upstreams emit (e.g. Wanxiang) dispatch by
        // model family instead.
        if (target.model.family == ModelFamily.openaiVideo) {
          return _openaiVideos.poll(target, operationName, logger: logger);
        }

        throw UnsupportedError('Operation "$operationName" is not recognized by the OpenAI protocol family.');
    }
  }

  /// Best-effort: ask upstream to stop an operation the user abandoned.
  ///
  /// Returns what upstream reports it did, or null when there was nothing to
  /// ask — which is the common case. Most video surfaces this app talks to
  /// have no cancel at all: a job, once submitted, runs and bills whether or
  /// not anyone is still waiting for it. Where a surface does have one, the
  /// protocol implements [CancellableJobProtocol] and owns the judgement of
  /// when calling it is safe (MiniMax's endpoint, for instance, *deletes* a
  /// finished task rather than cancelling it).
  ///
  /// Never throws for a refusal, and callers must not treat a null as a
  /// failure: the local task is going away either way, and this only decides
  /// whether the upstream one goes with it.
  Future<String?> cancelOperation(
    LLMModelConfig config,
    String operationName, {
    String? surfaceId,
    LLMLogger? logger,
  }) async {
    final target = resolveTarget(config);
    // Same provenance rule as checkOperation: a persisted surface names the
    // one place a cancel may go. If that surface has no cancel, the answer
    // is null — falling back to the channel's *current* declaration here
    // would aim the cancel at a surface the job never ran on.
    final surface = WireProtocol.tryParse(surfaceId);
    if (surface != null) {
      // Typed Object? so the `is!` test can promote: CancellableJobProtocol
      // is a sibling interface of VideoJobProtocol, not a subtype.
      final Object? pinned = _videoJobProtocolFor(surface);
      if (pinned is! CancellableJobProtocol) return null;
      return pinned.cancel(target, operationName, logger: logger);
    }
    final protocol = _cancellableJobProtocol(target);
    if (protocol == null) return null;
    return protocol.cancel(target, operationName, logger: logger);
  }

  /// The vendor-native async-video protocol a `videoProtocol` declaration
  /// names, or null when the vendor declares none.
  ///
  /// The single place that maps the declaration onto an implementation.
  /// Families that also have a default (①'s Sora-style `/v1/videos`) fall
  /// back to it themselves; ④ has no default, so for it a null here is the
  /// whole answer. Written once because [canRunVideoJob] has to give the
  /// model picker the same answer this gives routing — two switches drifting
  /// apart is how a model reaches a channel that then refuses it, or (worse)
  /// vanishes from the picker for a channel that would have served it.
  VideoJobProtocol? _nativeVideoProtocol(WireProtocol? declared) =>
      switch (declared) {
        WireProtocol.xaiVideos => _xaiVideos,
        WireProtocol.dashscopeVideo => _dashscopeVideo,
        WireProtocol.minimaxVideo => _minimaxVideo,
        WireProtocol.minimaxH3BaseVideo => _minimaxH3BaseVideo,
        _ => null,
      };

  /// The implementation behind *any* video-job surface — the superset of
  /// [_nativeVideoProtocol] that also answers for the two surfaces vendors
  /// never declare (①'s Sora-style default and Veo, which are family
  /// defaults rather than declarations). This is what a persisted
  /// [LLMOperationTicket.surfaceId] resolves through, so every surface a
  /// ticket can name must appear here; a non-video or unknown value answers
  /// null and the caller falls back to legacy routing.
  VideoJobProtocol? _videoJobProtocolFor(WireProtocol? surface) =>
      switch (surface) {
        WireProtocol.openaiVideos => _openaiVideos,
        WireProtocol.geminiVeo => _veo,
        _ => _nativeVideoProtocol(surface),
      };

  /// Whether this channel can start a video job for this model at all — the
  /// question the workbench's model picker asks before listing it.
  ///
  /// Mirrors [startLongRunning]'s branches exactly, and lives here so it
  /// cannot answer differently: the picker used to carry its own copy of the
  /// rule, and when a ④ vendor gained a native video surface the copy still
  /// said "the Anthropic family has no video", hiding the model from the UI
  /// while the route behind it worked.
  bool canRunVideoJob(LLMModelConfig config) {
    final target = resolveTarget(config);
    switch (target.vendor.family) {
      case ProtocolFamily.gemini:
        // Veo via `:predictLongRunning`.
        return true;
      case ProtocolFamily.midjourney:
        // Generation runs inside generate(); there is no job to start.
        return false;
      case ProtocolFamily.anthropic:
        // No family default — only a vendor-declared native surface.
        return target.model.family == ModelFamily.openaiVideo &&
            _nativeVideoProtocol(target.vendor.videoProtocol) != null;
      case ProtocolFamily.openai:
      case ProtocolFamily.dashscope:
        return target.model.family == ModelFamily.openaiVideo;
    }
  }

  /// The job protocol serving this target, if it can be cancelled upstream.
  ///
  /// Resolved through the same `videoProtocol` declaration [startLongRunning]
  /// and [checkOperation] route on, so a cancel can never reach a surface the
  /// task did not come from.
  CancellableJobProtocol? _cancellableJobProtocol(LLMTarget target) {
    final protocol = switch (target.vendor.videoProtocol) {
      WireProtocol.minimaxVideo => _minimaxVideo,
      _ => null,
    };
    return protocol is CancellableJobProtocol ? protocol : null;
  }

  // ---------------------------------------------------------------------------
  // Model discovery
  // ---------------------------------------------------------------------------

  Future<List<DiscoveredModel>> discoverModels(LLMModelConfig config) async {
    final target = resolveTarget(config);
    List<DiscoveredModel> listed;
    try {
      listed = await _fetchListedModels(target);
    } catch (_) {
      // The catalog's whole reason to exist is hosts whose listing endpoint
      // is missing — a stock SGLang H3-Base serve often has no
      // `GET /v1/models` at all — so it must survive the listing failing, or
      // "fetch models" errors out on exactly the deployment the catalog was
      // declared for and the user hand-types a repo-path id the vendor
      // already knows. A vendor that declares no catalog keeps the error:
      // there, the listing is the only possible answer.
      if (target.vendor.unlistedModels.isEmpty) rethrow;
      return mergeUnlistedModels(target.vendor, const []);
    }
    // Applied on every family rather than in the branches that need it, so
    // "does this vendor's catalog take effect here?" is never a per-family
    // question. A vendor that declares none passes through untouched.
    return mergeUnlistedModels(target.vendor, listed);
  }

  /// What this target's listing endpoint returns, on the face that serves it.
  Future<List<DiscoveredModel>> _fetchListedModels(LLMTarget target) {
    switch (target.vendor.family) {
      case ProtocolFamily.midjourney:
        return _midjourneyDiscovery.fetchModels(target);
      case ProtocolFamily.anthropic:
        return _anthropicDiscovery
            .fetchModels(_faceTarget(target, WireProtocol.anthropicChat));
      case ProtocolFamily.gemini:
        return _geminiDiscovery.fetchModels(target);
      case ProtocolFamily.openai:
      case ProtocolFamily.dashscope:
        // Both rewrite the base, for the same reason from opposite ends.
        // DashScope publishes no listing on its native surface — the only
        // `GET /models` it serves is on the compatible face of the same host,
        // under the same key. MiniMax serves one on each chat face but none
        // on `/v2`, where a user who followed the video doc may have pointed
        // the channel. Either way the listing lives on the vendor's chat
        // face, and that is what the derivation resolves to; the alternative
        // was a "fetch models" button that could only ever fail.
        return _openaiDiscovery
            .fetchModels(_faceTarget(target, WireProtocol.openaiChat));
    }
  }

}

/// [listed] plus [vendor]'s native-surface models
/// ([VendorProfile.unlistedModels]), minus any the listing already covered.
///
/// Appended rather than prepended: the live answer is the authoritative part
/// of the list, and a hardcoded id that upstream has since renamed should
/// read as a trailing extra, not as the headline.
///
/// Top-level rather than a method so it can be tested directly. The listing
/// half of discovery needs the network, so the one line in [
/// LLMDispatcher.discoverModels] that calls this is not itself covered —
/// deleting the call would leave the suite green. What is covered is every
/// rule the merge applies.
List<DiscoveredModel> mergeUnlistedModels(
    VendorProfile vendor, List<DiscoveredModel> listed) {
  final extra = vendor.unlistedBeyond(listed.map((m) => m.modelId));
  if (extra.isEmpty) return listed;
  return [
    ...listed,
    for (final m in extra)
      DiscoveredModel(
        modelId: m.id,
        displayName: m.id,
        description: m.description,
        // Marked so a reader of a saved model row can tell a catalog entry
        // from one the endpoint actually returned.
        rawData: {'id': m.id, 'source': 'vendor-catalog'},
      ),
  ];
}
