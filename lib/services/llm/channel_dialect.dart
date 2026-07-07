/// Channel "dialects" — the wire protocol and auth convention a channel speaks.
///
/// A channel's `type` (see [LLMChannel.type]) selects two things: which
/// [ILLMProvider] (and discovery provider) serves it, and how the API key is
/// presented on the wire.
///
/// New API relays expose two *native* formats that differ from the official
/// upstreams only in how the token is passed — both use an OpenAI-style bearer
/// token rather than Google's key conventions:
///  * [newApiOpenAI] — OpenAI-shaped requests → `openai-api` provider.
///  * [newApiGemini] — Gemini-shaped requests → `google-genai` provider, but
///    authenticated with `Authorization: Bearer` instead of `x-goog-api-key`
///    / the `?key=` query parameter.
class ChannelDialect {
  ChannelDialect._();

  /// Standard OpenAI-compatible REST (OpenAI official, relays, …).
  static const String openAIRest = 'openai-api-rest';

  /// Google Gemini REST, third-party relay or unspecified host.
  static const String googleRest = 'google-genai-rest';

  /// Google's first-party Gemini REST host (`*.googleapis.com`).
  static const String officialGoogle = 'official-google-genai-api';

  /// New API relay, OpenAI native format.
  static const String newApiOpenAI = 'newapi-openai';

  /// New API relay, Gemini native format (bearer-token auth).
  static const String newApiGemini = 'newapi-gemini';

  /// Midjourney via midjourney-proxy / NewAPI's `/mj/*` surface. The endpoint
  /// is the host root (e.g. `https://your-newapi-host.com`); the provider
  /// appends `/mj/submit/imagine` etc. Authenticated with bearer token.
  static const String midjourneyProxy = 'midjourney-proxy';

  /// xAI native REST (`https://api.x.ai/v1`). Chat/completions are
  /// OpenAI-compatible and go through the standard OpenAI transport, but
  /// video generation uses xAI's own async surface:
  /// `POST /videos/generations` → `GET /videos/{request_id}` (JSON, not the
  /// Sora-style multipart `/videos` endpoint). Bearer-token auth.
  static const String xaiApi = 'xai-api-rest';

  /// Channel dialects that speak the Google/Gemini wire format and are served
  /// by the `google-genai` provider.
  static const Set<String> _geminiDialects = {
    googleRest,
    officialGoogle,
    newApiGemini,
  };

  /// Channel dialects served by the `midjourney-proxy` provider.
  static const Set<String> _midjourneyDialects = {
    midjourneyProxy,
  };

  /// The registered [ILLMProvider] / discovery-provider key for [channelType].
  ///
  /// Everything that is not a Gemini or Midjourney dialect is served by the
  /// OpenAI transport (this includes [openAIRest] and [newApiOpenAI]).
  static String providerType(String channelType) {
    if (_geminiDialects.contains(channelType)) return 'google-genai';
    if (_midjourneyDialects.contains(channelType)) return 'midjourney-proxy';
    return 'openai-api';
  }

  /// True for New API's Gemini format, which authenticates with a bearer token
  /// (no `x-goog-api-key` header and no `?key=` query parameter).
  static bool isNewApiGemini(String channelType) =>
      channelType == newApiGemini;

  /// True for the xAI native dialect, which switches video generation from
  /// the Sora-style `/videos` multipart surface to xAI's
  /// `/videos/generations` JSON surface.
  static bool isXai(String channelType) => channelType == xaiApi;
}
