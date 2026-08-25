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

/// The call surface a request belongs to. A protocol serves exactly one
/// surface; a vendor may offer more than one protocol per surface (the menus
/// on [VendorProfile]), and a model may pick one of them
/// (`llm_models.wire_protocol`).
enum Surface { chat, imageGen, videoJob }

/// One concrete wire-protocol implementation the dispatcher can route to —
/// the unit of the per-surface menus below and of the per-model selection
/// stored in `llm_models.wire_protocol`.
///
/// [id] is the stable string stored in the database; renaming an enum value
/// is free, renaming an [id] is a data migration. Values are scarce on
/// purpose: only an implemented protocol earns one, so a stored id always
/// resolves to code that exists.
enum WireProtocol {
  openaiChat('openai-chat', Surface.chat),
  anthropicChat('anthropic-chat', Surface.chat),
  geminiChat('gemini-chat', Surface.chat),
  midjourney('midjourney', Surface.chat),
  openaiImages('openai-images', Surface.imageGen),
  xaiImages('xai-images', Surface.imageGen),
  geminiImagen('gemini-imagen', Surface.imageGen),
  dashscopeImagesSync('dashscope-images-sync', Surface.imageGen),
  dashscopeImagesAsync('dashscope-images-async', Surface.imageGen),
  openaiVideos('openai-videos', Surface.videoJob),
  xaiVideos('xai-videos', Surface.videoJob),
  geminiVeo('gemini-veo', Surface.videoJob),
  dashscopeVideo('dashscope-video', Surface.videoJob);

  final String id;
  final Surface surface;
  const WireProtocol(this.id, this.surface);

  /// The enum value a stored id names, or null for an unknown/legacy string —
  /// callers treat null as "auto", never as an error, so a database written
  /// by a newer build degrades to today's routing instead of failing.
  static WireProtocol? tryParse(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

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

  /// The chat-surface protocols this vendor serves beyond its [family]
  /// default, first entry first. Empty for the common single-face vendor —
  /// the dispatcher then routes by [family] exactly as before this field
  /// existed.
  ///
  /// A non-empty menu makes the *first* entry the vendor's chat default and
  /// the rest per-model alternates (`llm_models.wire_protocol`). More than
  /// one entry is what surfaces the protocol selector in the model editor;
  /// a single-entry menu renders no UI at all.
  final List<WireProtocol> chatMenu;

  /// The vendor-native image protocols serving the model families the
  /// dispatcher routes here (xAI's JSON surface, DashScope's native
  /// surface). Empty everywhere else — a relay listing `qwen-image` keeps
  /// its chat route, because the relay serves it through its own
  /// compatibility layer, not through these surfaces.
  ///
  /// First entry is the default; additional entries are per-model alternates
  /// (DashScope's sync/async pair), gated further by what the concrete model
  /// supports (layer 3).
  final List<WireProtocol> imageMenu;

  /// The vendor-native async-video protocol replacing the family default
  /// (`openaiVideos` / `geminiVeo`), or null to keep the family default.
  final WireProtocol? videoProtocol;

  /// Base-URL derivations for *generic* protocols this vendor serves on an
  /// alternate face — e.g. DashScope's Anthropic-compatible chat lives under
  /// `/apps/anthropic/v1` while the channel stores the compatible-mode base.
  /// The dispatcher rewrites the target's endpoint through this before
  /// handing it to the protocol, so the protocol itself stays vendor-blind.
  ///
  /// Vendor-specific protocols (the DashScope image/video ones) are not
  /// listed here: their path shape is the protocol's own knowledge and they
  /// derive it internally.
  final Map<WireProtocol, String Function(String endpoint)> protocolBases;

  /// Which `thinking` spelling this vendor understands, for the ④ surface.
  /// [ThinkingDialect.none] on every other family.
  final ThinkingDialect thinking;

  /// Whether this vendor understands ④'s `cache_control` breakpoints.
  ///
  /// Opt-in rather than on by default, because declaring it costs nothing to
  /// get right and a whole request to get wrong: marking the prefix requires
  /// sending `system` as a **block array** instead of a plain string, and a
  /// relay that reconstructs the payload rather than forwarding it may not
  /// accept that shape. A host that turns out not to support it fails the
  /// entire request, not just the caching.
  ///
  /// Meaningless outside ④ — ① and ③ have no equivalent and ignore the flag.
  final bool promptCaching;

  /// Whether a channel of this vendor can be saved with an empty API key.
  ///
  /// True only for the locally-hosted runtimes (Ollama, LM Studio), which
  /// serve an OpenAI-compatible surface on localhost with no auth at all.
  /// The key field stays on screen for them — someone may have put a
  /// reverse proxy in front — but it stops being required, because a user
  /// with no key to give was otherwise forced to type a junk character to
  /// get past the check.
  final bool keyOptional;

  const VendorProfile({
    required this.id,
    required this.family,
    required this.auth,
    this.chatMenu = const [],
    this.imageMenu = const [],
    this.videoProtocol,
    this.protocolBases = const {},
    this.thinking = ThinkingDialect.none,
    this.promptCaching = false,
    this.keyOptional = false,
  });

  /// The menu of protocols this vendor offers for [surface], honoring the
  /// family default when no explicit menu is declared. This is what the
  /// model editor renders (further intersected with what the concrete model
  /// supports — layer 3's business, applied by the dispatcher).
  List<WireProtocol> menuFor(Surface surface) {
    switch (surface) {
      case Surface.chat:
        if (chatMenu.isNotEmpty) return chatMenu;
        switch (family) {
          case ProtocolFamily.openai:
            return const [WireProtocol.openaiChat];
          case ProtocolFamily.gemini:
            return const [WireProtocol.geminiChat];
          case ProtocolFamily.anthropic:
            return const [WireProtocol.anthropicChat];
          case ProtocolFamily.midjourney:
            return const [WireProtocol.midjourney];
        }
      case Surface.imageGen:
        return imageMenu;
      case Surface.videoJob:
        return videoProtocol == null ? const [] : [videoProtocol!];
    }
  }

  /// Request headers for this vendor. [endpoint] is needed because
  /// [AuthScheme.googleApiKeyWithBearerFallback] keys off the endpoint host.
  Map<String, String> headers(String apiKey, String endpoint) {
    // An empty key is a real state now that [keyOptional] vendors exist, and
    // `Authorization: Bearer ` (empty value) is not the same request as no
    // Authorization header at all — some local runtimes and proxies reject
    // the former. Only the key-bearing headers drop out: `anthropic-version`
    // is a protocol requirement, not authentication, and must survive.
    // [downloadHeaders] and [decorateUrl] already guard on empty the same way.
    final bool keyed = apiKey.isNotEmpty;
    switch (auth) {
      case AuthScheme.bearer:
        return {
          'Content-Type': 'application/json',
          if (keyed) 'Authorization': 'Bearer $apiKey',
        };
      case AuthScheme.googleApiKey:
        return {
          'Content-Type': 'application/json',
          if (keyed) 'x-goog-api-key': apiKey,
        };
      case AuthScheme.googleApiKeyWithBearerFallback:
        final headers = {
          'Content-Type': 'application/json',
          if (keyed) 'x-goog-api-key': apiKey,
        };
        final host = Uri.tryParse(endpoint)?.host ?? '';
        if (keyed && !host.endsWith('googleapis.com')) {
          headers['Authorization'] = 'Bearer $apiKey';
        }
        return headers;
      case AuthScheme.anthropicApiKeyWithBearerFallback:
        final headers = {
          'Content-Type': 'application/json',
          if (keyed) 'x-api-key': apiKey,
          'anthropic-version': anthropicApiVersion,
        };
        final host = Uri.tryParse(endpoint)?.host ?? '';
        if (keyed && host != _anthropicOfficialHost) {
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
