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

  /// MiniMax's OpenAI-compatible endpoint. Body-compatible with [openAIRest];
  /// its specifics are response-side (inline `<think>` chains and the
  /// `base_resp.status_code` error envelope, both handled vendor-agnostically
  /// by the chat protocol).
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

  /// MiniMax's Anthropic-format endpoint (`/anthropic/v1`), the sibling of its
  /// OpenAI-format one at [minimax] — the same vendor serving two protocol
  /// families, which is why the family is a property of the channel and not of
  /// the company. Its documented divergences from Anthropic all land inside
  /// what this app already sends (`tool_choice: auto` only, `max_tokens`
  /// optional rather than required, `anthropic-version` not demanded), so it
  /// needs no behavior of its own — only its own id, so that the day one of
  /// them does diverge there is somewhere to put it.
  static const String minimaxAnthropic = 'minimax-anthropic';

  /// Alibaba DashScope (Bailian). Its chat is the OpenAI-compatible surface
  /// under `/compatible-mode/v1`, which is why the family is ① — but image
  /// generation is served *only* by DashScope's own `/api/v1` protocol, so
  /// the profile also claims [VendorProfile.usesDashScopeNativeImages] and
  /// the image protocol derives that base from this channel's endpoint. One
  /// channel, one key, both surfaces.
  static const String dashscope = 'dashscope-api';

  /// Midjourney via midjourney-proxy / NewAPI's `/mj/*` surface.
  static const String midjourneyProxy = 'midjourney-proxy';

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
      usesXaiNativeSurfaces: true,
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
    ),
    VendorProfile(
      id: anthropicRest,
      family: ProtocolFamily.anthropic,
      auth: AuthScheme.anthropicApiKeyWithBearerFallback,
      thinking: ThinkingDialect.anthropicBudget,
      // Anthropic's own endpoint, and the gateways that forward to it.
      promptCaching: true,
    ),
    VendorProfile(
      id: newApiAnthropic,
      family: ProtocolFamily.anthropic,
      auth: AuthScheme.anthropicApiKeyWithBearerFallback,
      // A relay of Claude, so Claude's spelling. A New API host fronting some
      // *other* ④ backend is the case this gets wrong — which is exactly why
      // [minimaxAnthropic] is its own profile rather than a note in a README.
      thinking: ThinkingDialect.anthropicBudget,
      promptCaching: true,
    ),
    VendorProfile(
      id: minimaxAnthropic,
      family: ProtocolFamily.anthropic,
      auth: AuthScheme.anthropicApiKeyWithBearerFallback,
      thinking: ThinkingDialect.adaptive,
      // Left off deliberately: MiniMax's ④ layer is the one that has already
      // been found missing pieces this app sends (no forcing tool_choice),
      // and an unsupported cache_control fails the whole request rather than
      // just the caching. Flip it once someone has run it against the live
      // endpoint.
    ),
    VendorProfile(
      id: dashscope,
      family: ProtocolFamily.openai,
      auth: AuthScheme.bearer,
      usesDashScopeNativeImages: true,
    ),
    VendorProfile(
      id: midjourneyProxy,
      family: ProtocolFamily.midjourney,
      auth: AuthScheme.bearer,
    ),
  ];

  static final Map<String, VendorProfile> _byId = {
    for (final v in all) v.id: v,
  };

  /// Profile for a channel's stored `type`. Unknown values fall back to the
  /// generic OpenAI-compatible profile — the historical behavior for any
  /// unrecognized channel type.
  static VendorProfile byId(String id) => _byId[id] ?? _byId[openAIRest]!;
}
