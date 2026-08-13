/// **Layer 2 — the vendor.**
///
/// A [VendorProfile] describes one *supplier* of a wire protocol: which
/// protocol family it speaks, how the API key is presented on the wire, and
/// which (if any) vendor-native surfaces replace the family defaults.
///
/// The profile's [id] is the string stored in `llm_channels.type` — the seven
/// historical channel-type values map 1:1 onto vendor profiles, so no channel
/// data migration is needed.
///
/// Layering rule: protocols (layer 1) may call [headers] / [decorateUrl] for
/// authentication, but must never branch on [id] — anything vendor-specific
/// beyond auth belongs either in a dedicated protocol implementation selected
/// by the dispatcher, or in a declarative flag on this profile.
library;

/// The wire-protocol family a vendor serves (**layer 1** identity).
///
/// * [openai] — OpenAI-style REST: `/chat/completions` (+ the sibling
///   `/images/*` and `/videos*` surfaces).
/// * [gemini] — Google GenAI REST: `/models/{m}:generateContent` (+ the
///   sibling `:predict` and `:predictLongRunning` surfaces).
/// * [midjourney] — the open-source midjourney-proxy REST surface (`/mj/*`).
enum ProtocolFamily { openai, gemini, midjourney }

/// How the API key is put on the wire.
enum AuthScheme {
  /// `Authorization: Bearer <key>` — OpenAI convention, also used by
  /// midjourney-proxy and by New API's Gemini-format relays.
  bearer,

  /// Google's key conventions: `x-goog-api-key` header *and* `?key=` query
  /// parameter (the query form survives header-stripping proxies). Never a
  /// bearer token — Google's own host treats one as an OAuth2 access token
  /// and rejects the request with 401.
  googleApiKey,

  /// [googleApiKey] plus an additional `Authorization: Bearer <key>` header
  /// for third-party hosts that emulate the Gemini dialect but expect
  /// OpenAI-style auth. The bearer header is suppressed automatically when
  /// the endpoint host is `*.googleapis.com`.
  googleApiKeyWithBearerFallback,
}

class VendorProfile {
  /// Stable id, stored verbatim in `llm_channels.type`.
  final String id;

  /// Which layer-1 protocol family this vendor serves.
  final ProtocolFamily family;

  final AuthScheme auth;

  /// True for vendors exposing xAI's native JSON surfaces: image generation
  /// via `/images/generations|edits` (JSON, not multipart) and async video
  /// via `/videos/generations` → `GET /videos/{request_id}`. The dispatcher
  /// swaps the family-default image/video protocols for the xAI ones.
  final bool usesXaiNativeSurfaces;

  const VendorProfile({
    required this.id,
    required this.family,
    required this.auth,
    this.usesXaiNativeSurfaces = false,
  });

  /// Request headers for this vendor. [endpoint] is needed because
  /// [AuthScheme.googleApiKeyWithBearerFallback] keys off the endpoint host.
  Map<String, String> headers(String apiKey, String endpoint) {
    switch (auth) {
      case AuthScheme.bearer:
        return {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        };
      case AuthScheme.googleApiKey:
        return {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        };
      case AuthScheme.googleApiKeyWithBearerFallback:
        final headers = {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        };
        final host = Uri.tryParse(endpoint)?.host ?? '';
        if (!host.endsWith('googleapis.com')) {
          headers['Authorization'] = 'Bearer $apiKey';
        }
        return headers;
    }
  }

  /// Vendor-specific URL decoration. Google-keyed vendors append the
  /// documented `?key=` query parameter (preserving existing parameters such
  /// as `alt=sse`); bearer vendors return the URL untouched so the key never
  /// leaks into a query string.
  Uri decorateUrl(Uri url, String apiKey) {
    if (auth == AuthScheme.bearer || apiKey.isEmpty) return url;
    return url.replace(queryParameters: {
      ...url.queryParameters,
      'key': apiKey,
    });
  }
}

/// Returns [url] with the `key` query parameter masked, safe for logging.
///
/// URLs built by [VendorProfile.decorateUrl] can embed the plaintext API key;
/// anything that prints a full request URL (console log, debug log files)
/// must go through this first so the key never leaves the process.
String redactUrl(Uri url) {
  if (!url.queryParameters.containsKey('key')) return url.toString();
  return url.replace(queryParameters: {
    ...url.queryParameters,
    'key': '***MASKED***',
  }).toString();
}
