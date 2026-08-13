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
