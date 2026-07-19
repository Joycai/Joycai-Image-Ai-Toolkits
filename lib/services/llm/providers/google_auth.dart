import '../channel_dialect.dart';

/// Auth/URL helpers for Google's REST dialect, shared by the GenAI provider and
/// model discovery. Kept separate from request orchestration so the logic stays
/// independently testable.

/// Builds the auth headers for Google's REST dialect.
///
/// Google's API key is passed in `x-goog-api-key`. The official Google host
/// (`*.googleapis.com`) treats an `Authorization: Bearer <api-key>` header as an
/// OAuth2 access token, fails to validate it, and returns 401 — so the bearer
/// token is only sent to third-party relays that emulate the dialect and may
/// expect OpenAI-style auth.
///
/// New API's Gemini format ([ChannelDialect.newApiGemini]) is the special case:
/// it authenticates *purely* with an OpenAI-style bearer token and rejects
/// requests carrying `x-goog-api-key`, so it gets the bearer header alone.
Map<String, String> buildGoogleAuthHeaders(
  String channelType,
  String apiKey,
  String endpoint,
) {
  if (ChannelDialect.isNewApiGemini(channelType)) {
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $apiKey",
    };
  }

  final headers = {
    "Content-Type": "application/json",
    "x-goog-api-key": apiKey,
  };
  final host = Uri.tryParse(endpoint)?.host ?? '';
  final isOfficialGoogle = host.endsWith('googleapis.com');
  if (channelType != ChannelDialect.officialGoogle && !isOfficialGoogle) {
    headers["Authorization"] = "Bearer $apiKey";
  }
  return headers;
}

/// Appends the API key as a `?key=` query parameter, matching Google's
/// documented REST examples (e.g. `...:generateContent?key=$GEMINI_API_KEY`).
///
/// This is equivalent to the `x-goog-api-key` header but is the most robust
/// form: it survives any proxy/relay that strips custom request headers.
/// Existing query parameters (such as `alt=sse`) are preserved.
///
/// New API's Gemini format authenticates with a bearer token only, so the key
/// is never leaked into the query string for that dialect.
Uri appendGoogleKey(Uri url, String apiKey, {String? channelType}) {
  if (apiKey.isEmpty) return url;
  if (channelType != null && ChannelDialect.isNewApiGemini(channelType)) {
    return url;
  }
  return url.replace(queryParameters: {
    ...url.queryParameters,
    'key': apiKey,
  });
}

/// Returns [url] with the `key` query parameter masked, safe for logging.
///
/// URLs built by [appendGoogleKey] embed the plaintext API key; anything that
/// prints a full request URL (console log, debug log files) must go through
/// this first so the key never leaves the process.
String redactUrl(Uri url) {
  if (!url.queryParameters.containsKey('key')) return url.toString();
  return url.replace(queryParameters: {
    ...url.queryParameters,
    'key': '***MASKED***',
  }).toString();
}
