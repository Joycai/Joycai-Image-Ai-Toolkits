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
/// * [anthropic] — Anthropic Messages: `POST /messages`, content-block
///   messages, typed SSE events.
enum ProtocolFamily { openai, gemini, midjourney, anthropic }

/// The `anthropic-version` every Anthropic-shaped request must carry.
///
/// Required by Anthropic's own host and by New API's relay of it; MiniMax's
/// compat endpoint does not require it but ignores it. There is no "latest"
/// alias — omitting the header is an error, not a request for the newest
/// version — so a client has to pin one, and this is the only version the
/// current `/messages` shape has ever been served under.
const String anthropicApiVersion = '2023-06-01';

/// Anthropic's own host. Auth differs here from everywhere else: it is the
/// one host that takes *only* `x-api-key`.
const String _anthropicOfficialHost = 'api.anthropic.com';

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

  /// Anthropic's `x-api-key` plus the mandatory `anthropic-version` header,
  /// and — for every host except Anthropic's own — an additional
  /// `Authorization: Bearer <key>`.
  ///
  /// The ④-family compat layers surveyed (New API, MiniMax) accept *either*
  /// spelling and document neither as preferred, while Anthropic itself takes
  /// only `x-api-key` and the `ANTHROPIC_AUTH_TOKEN → Bearer` convention is
  /// just as established in the ecosystem. Sending both is the only choice
  /// that needs no per-relay knowledge; the bearer header is suppressed on
  /// `api.anthropic.com` so a plain API key is never presented there as
  /// something it might be mistaken for.
  anthropicApiKeyWithBearerFallback,
}

/// How a ④ vendor spells "think before answering".
///
/// The two ④ hosts this app talks to do not share a vocabulary, so the
/// protocol cannot hardcode one and — by the layering rule — must not ask
/// which vendor it is talking to either. It reads this instead: layer 2 says
/// *which dialect*, layer 1 owns *what the JSON looks like*.
enum ThinkingDialect {
  /// No thinking control: the vendor either has none or decides for itself.
  /// Asking for thinking is then a no-op rather than a 400.
  none,

  /// Anthropic's own: `{"type": "enabled", "budget_tokens": N}`, where the
  /// budget is carved out of `max_tokens` and has a floor of 1024.
  anthropicBudget,

  /// MiniMax M3's: `{"type": "adaptive"}` — no budget to size, and **off**
  /// unless asked, which is the opposite of the current Claude generation.
  adaptive,
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

  /// Which `thinking` spelling this vendor understands, for the ④ surface.
  /// [ThinkingDialect.none] on every other family.
  final ThinkingDialect thinking;

  const VendorProfile({
    required this.id,
    required this.family,
    required this.auth,
    this.usesXaiNativeSurfaces = false,
    this.thinking = ThinkingDialect.none,
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
      case AuthScheme.anthropicApiKeyWithBearerFallback:
        final headers = {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': anthropicApiVersion,
        };
        final host = Uri.tryParse(endpoint)?.host ?? '';
        if (host != _anthropicOfficialHost) {
          headers['Authorization'] = 'Bearer $apiKey';
        }
        return headers;
    }
  }

  /// Headers for downloading a vendor-hosted asset — the video/image URI a
  /// generation job hands back, fetched with a plain GET from a CDN or relay
  /// rather than an API surface (so [headers]' Content-Type would be wrong
  /// and the full auth ritual unnecessary).
  ///
  /// Keyed off the auth scheme so the decision lives on this layer: the task
  /// executor used to branch on the protocol family itself, and since each
  /// side silently ignores the header it doesn't recognize, the next
  /// non-bearer vendor would have sent the wrong header with no error
  /// anywhere — just a 403 on download.
  Map<String, String> downloadHeaders(String apiKey) {
    if (apiKey.isEmpty) return const {};
    switch (auth) {
      case AuthScheme.googleApiKey:
      case AuthScheme.googleApiKeyWithBearerFallback:
        return {'x-goog-api-key': apiKey};
      case AuthScheme.bearer:
      case AuthScheme.anthropicApiKeyWithBearerFallback:
        return {'Authorization': 'Bearer $apiKey'};
    }
  }

  /// Vendor-specific URL decoration. Google-keyed vendors append the
  /// documented `?key=` query parameter (preserving existing parameters such
  /// as `alt=sse`); every other scheme returns the URL untouched so the key
  /// never leaks into a query string.
  ///
  /// Written as an exhaustive switch rather than "everything except bearer
  /// gets `?key=`": that spelling silently opted each *new* scheme into
  /// Google's query-parameter convention, so an Anthropic request would have
  /// gone out with the key in its URL — and into every log that prints one.
  Uri decorateUrl(Uri url, String apiKey) {
    if (apiKey.isEmpty) return url;
    switch (auth) {
      case AuthScheme.googleApiKey:
      case AuthScheme.googleApiKeyWithBearerFallback:
        return url.replace(queryParameters: {
          ...url.queryParameters,
          'key': apiKey,
        });
      case AuthScheme.bearer:
      case AuthScheme.anthropicApiKeyWithBearerFallback:
        return url;
    }
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
