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
    ),
    VendorProfile(
      id: newApiOpenAI,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
    ),
    VendorProfile(
      id: xaiApi,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
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
    ),
    VendorProfile(
      id: officialGoogle,
      family: ProtocolFamily.gemini,
      auth: AuthScheme.googleApiKey,
    ),
    VendorProfile(
      id: newApiGemini,
      family: ProtocolFamily.gemini,
      auth: AuthScheme.bearer,
    ),
    VendorProfile(
      id: deepseek,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
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
      // `{type: enabled, budget_tokens}` spelling. Ignored on the ① face.
      thinking: ThinkingDialect.anthropicBudget,
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

  /// The models behind MiniMax's two native surfaces, which neither chat
  /// face's `/models` returns (docs/api/minimax.md §5).
  ///
  /// Shared by both MiniMax profiles on purpose: which chat face a channel
  /// stores decides nothing about what the image and video endpoints serve.
  static const List<UnlistedModel> _minimaxNativeModels = [
    UnlistedModel('MiniMax-H3',
        description: 'Video generation (MiniMax /v2 task surface)'),
    UnlistedModel('image-01',
        description: 'Image generation (MiniMax /v1 surface)'),
    UnlistedModel('image-01-live',
        description: 'Image generation (MiniMax /v1 surface)'),
  ];

  static final Map<String, VendorProfile> _byId = {
    for (final v in all) v.id: v,
  };

  /// Profile for a channel's stored `type`. Unknown values fall back to the
  /// generic OpenAI-compatible profile — the historical behavior for any
  /// unrecognized channel type.
  static VendorProfile byId(String id) => _byId[id] ?? _byId[openAIRest]!;
}
