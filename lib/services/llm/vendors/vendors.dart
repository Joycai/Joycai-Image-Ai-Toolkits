import '../protocols/dashscope_payload.dart'
    show dashscopeAnthropicBase, dashscopeCompatibleBase;
import '../protocols/minimax_payload.dart'
    show minimaxAnthropicBase, minimaxOpenAIBase;
import 'vendor_profile.dart';

export 'vendor_profile.dart';

/// **Layer 2 registry** — every vendor the app knows how to talk to.
///
/// A "vendor" is a supplier of one of the three wire-protocol families:
/// an official host, a third-party relay, or another company exposing a
/// compatible surface with its own conventions. The [VendorProfile.id]
/// strings are stored in `llm_channels.type` and must stay stable.
///
/// Adding a vendor = adding one profile here (plus a wizard preset in the
/// UI). Only if the vendor speaks a genuinely new wire format does layer 1
/// (`protocols/`) need to grow.
class Vendors {
  Vendors._();

  /// Generic OpenAI-compatible REST — OpenAI official, Google's OpenAI-compat
  /// endpoint, DeepSeek-style compatible vendors, unspecified relays.
  static const String openAIRest = 'openai-api-rest';

  /// New API relay, OpenAI native format. Same wire behavior as [openAIRest];
  /// kept distinct so channels record which supplier they point at.
  static const String newApiOpenAI = 'newapi-openai';

  /// [openAIRest] led by the **Responses** face (`POST /responses`) instead of
  /// Chat Completions. Same host, key, discovery and media surfaces; the only
  /// difference is which chat wire a model rides when it has no pin, and a
  /// model can still pin Chat Completions. A channel-level choice because a
  /// user whose host serves only GPT-5.x wants every model on Responses
  /// without pinning each one (provider layering 01 §8.3: split rows when
  /// the choice belongs to the channel).
  static const String openAIResponsesRest = 'openai-responses-rest';

  /// [newApiOpenAI] led by the Responses face — the relay counterpart of
  /// [openAIResponsesRest].
  static const String newApiOpenAIResponses = 'newapi-openai-responses';

  /// xAI native REST (`https://api.x.ai/v1`). Chat is OpenAI-compatible;
  /// image and video generation use xAI's own JSON surfaces.
  static const String xaiApi = 'xai-api-rest';

  /// Google Gemini REST via a third-party relay or unspecified host.
  static const String googleRest = 'google-genai-rest';

  /// Google's first-party Gemini REST host (`*.googleapis.com`).
  static const String officialGoogle = 'official-google-genai-api';

  /// New API relay, Gemini native format — Gemini-shaped requests
  /// authenticated with an OpenAI-style bearer token.
  static const String newApiGemini = 'newapi-gemini';

  /// DeepSeek's official OpenAI-compatible endpoint
  /// (`https://api.deepseek.com`). Body-compatible with [openAIRest]; its
  /// specifics are response-side (`reasoning_content` echo-back is handled
  /// vendor-agnostically by the chat protocol) and future request extensions
  /// (`thinking: {type}`) will hang off this profile.
  static const String deepseek = 'deepseek-api';

  /// MiniMax reached through its **OpenAI-compatible** chat face
  /// (`/v1/chat/completions`). Chat is body-compatible with [openAIRest]; its
  /// specifics are response-side (inline `<think>` chains and the
  /// `base_resp.status_code` error envelope, both handled vendor-agnostically
  /// by the chat protocol).
  ///
  /// Chat is not all it serves, though — image generation
  /// (`/v1/image_generation`) and video (`/v2/video_generation`) are MiniMax's
  /// own surfaces, declared as menus below and derived from this one channel's
  /// endpoint. One channel, one key, every face (docs/api/minimax.md).
  static const String minimax = 'minimax-api';

  /// Anthropic Messages REST — Anthropic's own host, or any other supplier of
  /// the native `POST /messages` surface (MiniMax's `/anthropic/v1`, a
  /// self-hosted gateway, an unspecified relay). One profile covers both
  /// because the only thing that actually differs is auth, and that is keyed
  /// off the endpoint host rather than off the channel type.
  static const String anthropicRest = 'anthropic-api-rest';

  /// New API relay, Anthropic native format. Same wire behavior as
  /// [anthropicRest]; kept distinct so channels record their supplier, exactly
  /// as [newApiOpenAI] does for ①.
  static const String newApiAnthropic = 'newapi-anthropic';

  /// MiniMax reached through its **Anthropic-format** chat face
  /// (`/anthropic/v1/messages`), the sibling of its OpenAI-format one at
  /// [minimax] — the same vendor serving two protocol families, which is why
  /// the family is a property of the channel and not of the company. Its
  /// documented divergences from Anthropic all land inside what this app
  /// already sends (`tool_choice: auto` only, `max_tokens` optional rather
  /// than required, `anthropic-version` not demanded), so its chat needs no
  /// behavior of its own — only its own id, so that the day one of them does
  /// diverge there is somewhere to put it.
  ///
  /// The image and video surfaces below are the *same* ones [minimax]
  /// declares: they live on `/v1` and `/v2` of this host regardless of which
  /// chat face the channel leads with, and the endpoint each needs is derived
  /// from the stored one. Which chat wire a channel speaks is a choice; which
  /// image endpoint MiniMax has is not.
  static const String minimaxAnthropic = 'minimax-anthropic';

  /// Alibaba DashScope (Bailian). Its chat default is the OpenAI-compatible
  /// surface under `/compatible-mode/v1`, which is why the family is ① — but
  /// it is the app's first true multi-face vendor: an Anthropic-compatible
  /// chat alternate (`/apps/anthropic/v1`), a native image surface (sync +
  /// async task), and a native async video surface, all declared as surface
  /// menus on the profile and all derived from this one channel's endpoint.
  /// One channel, one key, every face (docs/api/qianwen-bailian.md).
  static const String dashscope = 'dashscope-api';

  /// Alibaba DashScope reached through its **native** REST
  /// (`/api/v1/services/aigc/*`) rather than its compatible face.
  ///
  /// The same company, host and key as [dashscope] — what differs is which
  /// chat wire the channel leads with, and that is a property of the channel
  /// because the two faces are two base URLs, not two models. Native is the
  /// face DashScope ships parameters on first, and the only one that serves
  /// `qwen-audio`; the compatible face is the one every OpenAI-shaped client
  /// already speaks. Both channels can still reach all three chat wires per
  /// model — the vendor only decides the default.
  static const String dashscopeNative = 'dashscope-native';

  /// Volcengine Ark (火山方舟) — ByteDance's model platform
  /// (docs/api/volcengine-ark.md). Chat is OpenAI-compatible at
  /// `{base}/chat/completions`, which makes the family ①; image generation is
  /// Seedream on Ark's own body at `{base}/images/generations`, declared as the
  /// image menu.
  ///
  /// Two bases serve the same paths — pay-as-you-go `…/api/v3` and the
  /// subscription plan's `…/api/plan/v3` — with keys that do not cross over.
  /// That is a difference of address, not of behaviour, so it is one vendor
  /// and two wizard variants that write different endpoints.
  static const String volcengineArk = 'volcengine-ark';

  /// Midjourney via midjourney-proxy / NewAPI's `/mj/*` surface.
  static const String midjourneyProxy = 'midjourney-proxy';

  /// Ollama's OpenAI-compatible surface (`http://localhost:11434/v1`).
  ///
  /// Body-compatible with [openAIRest]; its own id exists so a channel
  /// records that it points at a local runtime rather than at a hosted
  /// supplier, and so [VendorProfile.keyOptional] can be true here without
  /// loosening the requirement for every generic OpenAI-compatible channel.
  static const String ollama = 'ollama';

  /// LM Studio's OpenAI-compatible server (`http://localhost:1234/v1`).
  /// Same reasoning as [ollama].
  static const String lmStudio = 'lm-studio';

  /// A self-hosted MiniMax H3 video service — the SGLang "H3-Base API"
  /// (`sglang serve --model-path MiniMaxAI/MiniMax-H3`, quickstart at
  /// `http://127.0.0.1:30010/v1`). The official local route for the model:
  /// the open H3-Base weights run under SGLang/ComfyUI, *not* under the
  /// text-LLM runtimes above — LM Studio has no video surface at all.
  ///
  /// Not folded into [minimax]: same model family, different wire. The cloud
  /// `/v2/video_generation` task flow and the local Sora-shaped `/v1/videos`
  /// share neither a body vocabulary nor a status word (docs/api/minimax.md
  /// §4 vs §8), and this host serves exactly one surface — no chat, no
  /// images, no `/v2`. Local-runtime conventions apply otherwise: no auth by
  /// default ([VendorProfile.keyOptional]), bearer only for a fronting proxy.
  static const String minimaxH3Base = 'minimax-h3-base';

  static const List<VendorProfile> all = [
    VendorProfile(
      id: openAIRest,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // ① stays the default; the Responses API is a per-model alternate on
      // the same base and key (OpenAI has Responses-only models — provider
      // layering 01 §8.1).
      chatMenu: _openaiChatFaces,
      // OpenAI itself serves `/images` and `/videos`, and an unspecified
      // relay's model names are free text — the generic media surfaces have
      // to be on the menu for a user to correct a guess.
      offersFamilyMediaSurfaces: true,
    ),
    VendorProfile(
      id: newApiOpenAI,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // New API relays `/v1/responses` beside `/v1/chat/completions`
      // (provider layering 01 §9.2).
      chatMenu: _openaiChatFaces,
      offersFamilyMediaSurfaces: true,
    ),
    VendorProfile(
      id: openAIResponsesRest,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // The same menu as [openAIRest], Responses first: the first entry is
      // the chat default, the other stays a per-model alternate.
      chatMenu: _responsesLedChatFaces,
      offersFamilyMediaSurfaces: true,
    ),
    VendorProfile(
      id: newApiOpenAIResponses,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      chatMenu: _responsesLedChatFaces,
      offersFamilyMediaSurfaces: true,
    ),
    VendorProfile(
      id: xaiApi,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // xAI marks Responses as its recommended interface and Chat
      // Completions as deprecated (provider layering 01 §9.1), so Responses
      // leads: every unpinned chat model on an xAI channel rides it, and
      // Chat Completions stays a per-model pin for anything that needs it.
      chatMenu: _responsesLedChatFaces,
      // Without it xAI's reasoning items carry no `encrypted_content`, and a
      // replay without it still answers — the reasoning just stops carrying
      // over (reasoning 03 §7.3).
      responsesIncludeEncryptedReasoning: true,
      // xAI's own JSON surfaces replace the family defaults: images via
      // `/images/generations|edits` (JSON, not multipart), async video via
      // `/videos/generations` → `GET /videos/{request_id}`.
      imageMenu: [WireProtocol.xaiImages],
      videoProtocol: WireProtocol.xaiVideos,
    ),
    VendorProfile(
      id: googleRest,
      family: ProtocolFamily.gemini,
      auth: AuthScheme.googleApiKeyWithBearerFallback,
      offersFamilyMediaSurfaces: true,
    ),
    VendorProfile(
      id: officialGoogle,
      family: ProtocolFamily.gemini,
      auth: AuthScheme.googleApiKey,
      offersFamilyMediaSurfaces: true,
    ),
    VendorProfile(
      id: newApiGemini,
      family: ProtocolFamily.gemini,
      auth: AuthScheme.bearer,
      offersFamilyMediaSurfaces: true,
    ),
    VendorProfile(
      id: deepseek,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // DeepSeek's off switch is the top-level `thinking` object, not
      // `reasoning_effort: none` — see [ThinkingDialect.openaiThinkingObject].
      // Only this vendor: the generic ① profile must never send the object.
      thinking: ThinkingDialect.openaiThinkingObject,
    ),
    VendorProfile(
      id: minimax,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // Chat rides the ① family default; the other two surfaces are MiniMax's
      // own and have no OpenAI-compatible equivalent to fall back to —
      // `/v1/image_generation` is not the Images API, and `/v2` video is a
      // task flow with its own status vocabulary.
      imageMenu: [WireProtocol.minimaxImages],
      videoProtocol: WireProtocol.minimaxVideo,
      // The chat face derives too, not just the native ones. MiniMax's four
      // wires share no common prefix (docs/api/minimax.md §0), so a user who
      // read the video doc and stored `…/v2` gets a channel whose images and
      // video work — those derive — while chat and model discovery 404 on
      // `/v2/chat/completions` and `/v2/models`. One channel reaching every
      // face is the whole design; the generic protocols were the half of it
      // still keyed off the raw string.
      protocolBases: {
        WireProtocol.openaiChat: minimaxOpenAIBase,
      },
      unlistedModels: _minimaxNativeModels,
    ),
    VendorProfile(
      id: anthropicRest,
      family: ProtocolFamily.anthropic,
      auth: AuthScheme.anthropicApiKeyWithBearerFallback,
      // The current generation's spelling. Claude 4.7+ answers the manual
      // `enabled` + `budget_tokens` form with a 400, so the vendor default
      // is adaptive; 4.5 and earlier — which know only the manual form —
      // are recognized by layer 3 and switched back per model, and anything
      // the id rules miss is caught by the protocol's one-shot retry on a
      // thinking-shaped 400.
      thinking: ThinkingDialect.anthropicAdaptive,
      // Anthropic's own endpoint, and the gateways that forward to it.
      promptCaching: true,
    ),
    VendorProfile(
      id: newApiAnthropic,
      family: ProtocolFamily.anthropic,
      auth: AuthScheme.anthropicApiKeyWithBearerFallback,
      // A relay of Claude, so Claude's spelling — the same default and the
      // same per-model / on-400 fallback as [anthropicRest]. A New API host
      // fronting some *other* ④ backend is the case this gets wrong — which
      // is exactly why [minimaxAnthropic] is its own profile rather than a
      // note in a README.
      thinking: ThinkingDialect.anthropicAdaptive,
      promptCaching: true,
    ),
    VendorProfile(
      id: minimaxAnthropic,
      family: ProtocolFamily.anthropic,
      auth: AuthScheme.anthropicApiKeyWithBearerFallback,
      thinking: ThinkingDialect.adaptive,
      // The same two native surfaces its ① sibling declares. A ④ vendor with
      // an image menu is a first — the family's own answer is "there is no
      // image surface" — which is why the dispatcher's anthropic branches
      // check the declaration rather than assuming the family.
      imageMenu: [WireProtocol.minimaxImages],
      videoProtocol: WireProtocol.minimaxVideo,
      // The two native protocols are not listed in `protocolBases`: each owns
      // its path shape and derives its own base from the stored endpoint
      // (`/v1` for images, `/v2` for video) — which is what lets this channel
      // and its ① sibling reach them from either stored face. The entry below
      // is for the *chat* face, the one generic protocol here, so that it
      // derives from the stored endpoint the same way.
      protocolBases: {
        WireProtocol.anthropicChat: minimaxAnthropicBase,
      },
      unlistedModels: _minimaxNativeModels,
      //
      // promptCaching left off deliberately: MiniMax's ④ layer is the one
      // that has already been found missing pieces this app sends (no forcing
      // tool_choice), and an unsupported cache_control fails the whole
      // request rather than just the caching. Flip it once someone has run it
      // against the live endpoint.
    ),
    VendorProfile(
      id: dashscope,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // One channel, one key, every face (docs/api/qianwen-bailian.md).
      // Chat defaults to the compatible-mode surface; the Anthropic face
      // (`/apps/anthropic/v1`) and the native one (`/api/v1/services/aigc/*`)
      // are per-model alternates, both derived from the same stored endpoint
      // — which is what makes `qwen-audio`, served on the native wire alone,
      // reachable from a compatible-mode channel. Images default to the
      // native synchronous surface with the async task flow as a per-model
      // alternate (only offered where layer 3 says the model supports it);
      // video is the native async task surface — wan3.x has no other route.
      chatMenu: [
        WireProtocol.openaiChat,
        WireProtocol.anthropicChat,
        WireProtocol.dashscopeChat,
      ],
      imageMenu: [
        WireProtocol.dashscopeImagesSync,
        WireProtocol.dashscopeImagesAsync,
      ],
      videoProtocol: WireProtocol.dashscopeVideo,
      protocolBases: {
        WireProtocol.anthropicChat: dashscopeAnthropicBase,
      },
      // For the ④ face: Bailian documents the official
      // `{type: enabled, budget_tokens}` spelling.
      thinking: ThinkingDialect.anthropicBudget,
      // The ① face spells thinking as the `enable_thinking` switch rather
      // than `reasoning_effort` — see [ThinkingDialect.openaiEnableThinking].
      thinkingByProtocol: _dashscopeThinkingByFace,
      serverWebSearchFaces: _dashscopeSearchFaces,
    ),
    VendorProfile(
      id: dashscopeNative,
      family: ProtocolFamily.dashscope,
      auth: AuthScheme.bearer,
      // The mirror of [dashscope]: the same three chat faces and the same
      // native image/video surfaces, led by the native wire instead of the
      // compatible one. Both alternates are generic protocols served on
      // another base of the same host, so both are derived rather than
      // stored — a channel configured with `…/api/v1` still reaches them.
      chatMenu: [
        WireProtocol.dashscopeChat,
        WireProtocol.openaiChat,
        WireProtocol.anthropicChat,
      ],
      imageMenu: [
        WireProtocol.dashscopeImagesSync,
        WireProtocol.dashscopeImagesAsync,
      ],
      videoProtocol: WireProtocol.dashscopeVideo,
      protocolBases: {
        WireProtocol.openaiChat: dashscopeCompatibleBase,
        WireProtocol.anthropicChat: dashscopeAnthropicBase,
      },
      thinking: ThinkingDialect.anthropicBudget,
      // The same per-face declaration as its compatible sibling: which chat
      // wire a model rides decides the spelling, not which one the channel
      // leads with.
      thinkingByProtocol: _dashscopeThinkingByFace,
      serverWebSearchFaces: _dashscopeSearchFaces,
    ),
    VendorProfile(
      id: volcengineArk,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // Seedream's surface. No generic media surfaces: Ark serves no
      // `/images/edits` and draws nothing through chat, so offering them
      // would put two guaranteed failures on the menu.
      imageMenu: [WireProtocol.arkImages],
      // Neither base answers `GET /models` for image models (the plan's is a
      // 404, measured), so "fetch models" would otherwise never list the
      // models this channel type exists for.
      unlistedModels: _arkSeedreamModels,
    ),
    VendorProfile(
      id: midjourneyProxy,
      family: ProtocolFamily.midjourney,
      auth: AuthScheme.bearer,
    ),
    VendorProfile(
      id: ollama,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      // No auth by default; the bearer scheme only matters when someone has
      // put a reverse proxy in front, and [VendorProfile.headers] omits the
      // header entirely while the key is empty.
      keyOptional: true,
    ),
    VendorProfile(
      id: lmStudio,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      keyOptional: true,
    ),
    VendorProfile(
      id: minimaxH3Base,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      keyOptional: true,
      // The one surface this host serves. Declared as the vendor-native
      // video protocol (replacing the ① Sora-style default) because the
      // shared path shape is where the resemblance ends: JSON task body,
      // `completed` as the terminal status.
      videoProtocol: WireProtocol.minimaxH3BaseVideo,
      // SGLang's `GET /models` — when the serve variant exposes it at all —
      // describes the loaded checkpoint, and an H3-Base process serves
      // nothing else; the catalog entry keeps "fetch models" meaningful
      // either way, spelled the way the generation endpoint expects it
      // (the HuggingFace repo path, not the cloud id).
      unlistedModels: [
        UnlistedModel('MiniMaxAI/MiniMax-H3',
            description: 'Video generation (self-hosted SGLang /v1/videos)'),
      ],
    ),
  ];

  /// The OpenAI-shaped hosts that also serve the Responses API: Chat
  /// Completions first (the default every existing channel already rides),
  /// Responses as the per-model alternate.
  static const List<WireProtocol> _openaiChatFaces = [
    WireProtocol.openaiChat,
    WireProtocol.openaiResponses,
  ];

  /// The same two faces, Responses first — for the channel types a user picks
  /// when the whole channel should default to the Responses API.
  static const List<WireProtocol> _responsesLedChatFaces = [
    WireProtocol.openaiResponses,
    WireProtocol.openaiChat,
  ];

  /// The models behind MiniMax's two native surfaces, which neither chat
  /// face's `/models` returns (docs/api/minimax.md §5).
  ///
  /// Shared by both MiniMax profiles on purpose: which chat face a channel
  /// stores decides nothing about what the image and video endpoints serve.
  /// Bailian's per-face thinking spellings, shared by both of its vendors:
  /// the ① face takes the `enable_thinking` switch. The ④ face keeps the
  /// vendor default (the manual budget form), and the native face spells
  /// `parameters.enable_thinking` itself.
  static const Map<WireProtocol, ThinkingDialect> _dashscopeThinkingByFace = {
    WireProtocol.openaiChat: ThinkingDialect.openaiEnableThinking,
  };

  /// The Bailian chat faces that take the traceless `enable_search` switch:
  /// top level on the compatible face, `parameters` on the native one
  /// (help.aliyun.com Model Studio web search). Not the ④ face — nothing is
  /// documented for it there.
  static const Set<WireProtocol> _dashscopeSearchFaces = {
    WireProtocol.openaiChat,
    WireProtocol.dashscopeChat,
  };

  static const List<UnlistedModel> _minimaxNativeModels = [
    UnlistedModel('MiniMax-H3',
        description: 'Video generation (MiniMax /v2 task surface)'),
    UnlistedModel('image-01',
        description: 'Image generation (MiniMax /v1 surface)'),
    UnlistedModel('image-01-live',
        description: 'Image generation (MiniMax /v1 surface)'),
  ];

  /// Seedream on Ark: the dated ids pay-as-you-go serves, then the two
  /// undated aliases the subscription plan documents — the plan serves only
  /// the 5.0 pair, and names them this way (docs/api/volcengine-ark.md §7).
  static const List<UnlistedModel> _arkSeedreamModels = [
    UnlistedModel('doubao-seedream-5-0-pro-260628',
        description: 'Seedream 5.0 pro · image generation (Ark)'),
    UnlistedModel('doubao-seedream-5-0-lite-260128',
        description: 'Seedream 5.0 lite · image generation (Ark)'),
    UnlistedModel('doubao-seedream-4-5-251128',
        description: 'Seedream 4.5 · image generation (Ark, pay-as-you-go)'),
    UnlistedModel('doubao-seedream-4-0-250828',
        description: 'Seedream 4.0 · image generation (Ark, pay-as-you-go)'),
    UnlistedModel('doubao-seedream-5.0-pro',
        description: 'Seedream 5.0 pro · image generation (Ark plan)'),
    UnlistedModel('doubao-seedream-5.0-lite',
        description: 'Seedream 5.0 lite · image generation (Ark plan)'),
  ];

  static final Map<String, VendorProfile> _byId = {
    for (final v in all) v.id: v,
  };

  /// Profile for a channel's stored `type`. Unknown values fall back to the
  /// generic OpenAI-compatible profile — the historical behavior for any
  /// unrecognized channel type.
  static VendorProfile byId(String id) => _byId[id] ?? _byId[openAIRest]!;
}
