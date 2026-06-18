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

  /// Channel dialects that speak the Google/Gemini wire format and are served
  /// by the `google-genai` provider.
  static const Set<String> _geminiDialects = {
    googleRest,
    officialGoogle,
    newApiGemini,
  };

  /// The registered [ILLMProvider] / discovery-provider key for [channelType].
  ///
  /// Everything that is not a Gemini dialect is served by the OpenAI transport
  /// (this includes [openAIRest] and [newApiOpenAI]).
  static String providerType(String channelType) =>
      _geminiDialects.contains(channelType) ? 'google-genai' : 'openai-api';

  /// True for New API's Gemini format, which authenticates with a bearer token
  /// (no `x-goog-api-key` header and no `?key=` query parameter).
  static bool isNewApiGemini(String channelType) =>
      channelType == newApiGemini;
}
