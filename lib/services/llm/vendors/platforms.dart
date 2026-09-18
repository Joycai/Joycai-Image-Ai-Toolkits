import 'vendors.dart';

/// **The platform layer above [VendorProfile]** — which company or kind of
/// host a channel points at, and which routes that host offers.
///
/// A channel's stored `type` used to answer two questions at once: *which
/// platform* (New API, Bailian, MiniMax…) and *which chat protocol leads*
/// (`newapi-openai` vs `newapi-gemini`, `minimax-api` vs
/// `minimax-anthropic`). One key speaking four protocols therefore needed
/// four channels. A [PlatformProfile] separates the two: the platform owns a
/// table of routes, one per [RouteKind], and each route resolves to the
/// vendor profile that serves it. The vendor table itself is unchanged — a
/// vendor id is now the leaf of the lookup (platform, route) → profile.
///
/// Platforms ship with the app and are never stored. A channel's platform is
/// inferred from its primary route's vendor and host ([inferPlatform]), so an
/// improvement to this table reaches every existing channel without a
/// migration, and saving a channel can never freeze an old inference.
/// (Standard `channel-route-model` 01 §4.)

/// One route family: a chat wire at an address. At most one per channel.
///
/// [id] is the string stored in `llm_channels.routes` and
/// `llm_models.active_route`; renaming a value is free, renaming an id is a
/// data migration. Image and video surfaces are *not* routes — they are
/// dedicated endpoints a model picks with its media protocol selection, and
/// they ride the channel's primary route.
enum RouteKind {
  chat('chat', WireProtocol.openaiChat),
  responses('responses', WireProtocol.openaiResponses),
  anthropic('anthropic', WireProtocol.anthropicChat),
  gemini('gemini', WireProtocol.geminiChat),
  dashscope('dashscope', WireProtocol.dashscopeChat),
  midjourney('midjourney', WireProtocol.midjourney);

  const RouteKind(this.id, this.face);

  final String id;

  /// The chat wire this route speaks.
  final WireProtocol face;

  static RouteKind? tryParse(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// The route a chat wire belongs to, or null for a non-chat wire.
  static RouteKind? ofFace(WireProtocol face) {
    for (final k in values) {
      if (k.face == face) return k;
    }
    return null;
  }
}

/// One route a platform offers: its default path (joined to the channel's
/// host) and the vendor profile that serves it.
class PlatformRoute {
  final RouteKind kind;

  /// Joined to the channel host when the route stores no override. Empty
  /// means the host itself (DeepSeek, Midjourney proxies).
  final String defaultPath;

  final String vendorId;

  const PlatformRoute(this.kind, this.defaultPath, this.vendorId);
}

/// A platform: the routes it offers, in the order a new channel creates them
/// (the first is the default primary), and the hosts it is recognized by.
class PlatformProfile {
  final String id;

  /// Scheme + host a new channel starts from, or null where the user brings
  /// their own (relays, custom endpoints, local runtimes on a chosen port).
  final String? officialHost;

  /// Lower-case host names this platform is inferred from — exact, or a
  /// suffix when the entry starts with a dot.
  final List<String> hosts;

  final List<PlatformRoute> routes;

  /// The user supplies the host (relays and custom endpoints).
  final bool hostFromUser;

  const PlatformProfile({
    required this.id,
    required this.routes,
    this.officialHost,
    this.hosts = const [],
    this.hostFromUser = false,
  });

  PlatformRoute? route(RouteKind kind) {
    for (final r in routes) {
      if (r.kind == kind) return r;
    }
    return null;
  }

  bool offers(RouteKind kind) => route(kind) != null;

  bool matchesHost(String host) {
    for (final h in hosts) {
      if (h.startsWith('.') ? host.endsWith(h) : host == h) return true;
    }
    return false;
  }
}

class Platforms {
  Platforms._();

  static const String openai = 'openai';
  static const String anthropic = 'anthropic';
  static const String google = 'google';
  static const String xai = 'xai';
  static const String deepseek = 'deepseek';
  static const String minimax = 'minimax';
  static const String dashscope = 'dashscope';
  static const String ark = 'ark';
  static const String newapi = 'newapi';
  static const String midjourney = 'midjourney';
  static const String ollama = 'ollama';
  static const String lmStudio = 'lmstudio';
  static const String h3Base = 'h3base';

  /// Anything no other profile claims: only the protocol-standard part of
  /// each route, no private extension. A legitimate platform, not an error
  /// state (standard 01 §4 rule 2).
  static const String custom = 'custom';

  static const List<PlatformProfile> all = [
    PlatformProfile(
      id: openai,
      officialHost: 'https://api.openai.com',
      hosts: ['api.openai.com'],
      routes: [
        PlatformRoute(RouteKind.chat, '/v1', Vendors.openAIRest),
        PlatformRoute(RouteKind.responses, '/v1', Vendors.openAIResponsesRest),
      ],
    ),
    PlatformProfile(
      id: anthropic,
      officialHost: 'https://api.anthropic.com',
      hosts: ['api.anthropic.com'],
      routes: [
        PlatformRoute(RouteKind.anthropic, '/v1', Vendors.anthropicRest),
      ],
    ),
    PlatformProfile(
      id: google,
      officialHost: 'https://generativelanguage.googleapis.com',
      hosts: ['generativelanguage.googleapis.com'],
      routes: [
        PlatformRoute(RouteKind.gemini, '/v1beta', Vendors.googleRest),
        // Google's OpenAI-compatible face on the same host and key.
        PlatformRoute(RouteKind.chat, '/v1beta/openai', Vendors.openAIRest),
      ],
    ),
    PlatformProfile(
      id: xai,
      officialHost: 'https://api.x.ai',
      hosts: ['api.x.ai'],
      routes: [
        PlatformRoute(RouteKind.responses, '/v1', Vendors.xaiApi),
        PlatformRoute(RouteKind.chat, '/v1', Vendors.xaiApi),
      ],
    ),
    PlatformProfile(
      id: deepseek,
      officialHost: 'https://api.deepseek.com',
      hosts: ['api.deepseek.com'],
      routes: [PlatformRoute(RouteKind.chat, '', Vendors.deepseek)],
    ),
    PlatformProfile(
      id: minimax,
      officialHost: 'https://api.minimaxi.com',
      hosts: ['api.minimaxi.com', 'api.minimax.io', 'api.minimax.chat'],
      routes: [
        PlatformRoute(RouteKind.chat, '/v1', Vendors.minimax),
        PlatformRoute(
          RouteKind.anthropic,
          '/anthropic/v1',
          Vendors.minimaxAnthropic,
        ),
      ],
    ),
    PlatformProfile(
      id: dashscope,
      officialHost: 'https://dashscope.aliyuncs.com',
      hosts: ['dashscope.aliyuncs.com', 'dashscope-intl.aliyuncs.com'],
      routes: [
        PlatformRoute(RouteKind.chat, '/compatible-mode/v1', Vendors.dashscope),
        PlatformRoute(
          RouteKind.anthropic,
          '/apps/anthropic/v1',
          Vendors.dashscope,
        ),
        PlatformRoute(RouteKind.dashscope, '/api/v1', Vendors.dashscopeNative),
      ],
    ),
    PlatformProfile(
      id: ark,
      officialHost: 'https://ark.cn-beijing.volces.com',
      hosts: ['.volces.com'],
      routes: [PlatformRoute(RouteKind.chat, '/api/v3', Vendors.volcengineArk)],
    ),
    PlatformProfile(
      id: newapi,
      hostFromUser: true,
      routes: [
        PlatformRoute(RouteKind.chat, '/v1', Vendors.newApiOpenAI),
        PlatformRoute(
          RouteKind.responses,
          '/v1',
          Vendors.newApiOpenAIResponses,
        ),
        PlatformRoute(RouteKind.anthropic, '/v1', Vendors.newApiAnthropic),
        PlatformRoute(RouteKind.gemini, '/v1beta', Vendors.newApiGemini),
      ],
    ),
    PlatformProfile(
      id: midjourney,
      hostFromUser: true,
      routes: [
        PlatformRoute(RouteKind.midjourney, '', Vendors.midjourneyProxy),
      ],
    ),
    PlatformProfile(
      id: ollama,
      officialHost: 'http://localhost:11434',
      routes: [PlatformRoute(RouteKind.chat, '/v1', Vendors.ollama)],
    ),
    PlatformProfile(
      id: lmStudio,
      officialHost: 'http://localhost:1234',
      routes: [PlatformRoute(RouteKind.chat, '/v1', Vendors.lmStudio)],
    ),
    PlatformProfile(
      id: h3Base,
      officialHost: 'http://127.0.0.1:30010',
      routes: [PlatformRoute(RouteKind.chat, '/v1', Vendors.minimaxH3Base)],
    ),
    PlatformProfile(
      id: custom,
      hostFromUser: true,
      routes: [
        PlatformRoute(RouteKind.chat, '/v1', Vendors.openAIRest),
        PlatformRoute(RouteKind.responses, '/v1', Vendors.openAIResponsesRest),
        PlatformRoute(RouteKind.anthropic, '/v1', Vendors.anthropicRest),
        PlatformRoute(RouteKind.gemini, '/v1beta', Vendors.googleRest),
      ],
    ),
  ];

  static final Map<String, PlatformProfile> _byId = {
    for (final p in all) p.id: p,
  };

  /// The profile for [id]; unknown ids (a newer build's platform) read as
  /// [custom] — only the protocol-standard part, nothing private.
  static PlatformProfile byId(String id) => _byId[id] ?? _byId[custom]!;

  /// Vendors that name their platform outright, whatever the host.
  static const Map<String, String> _platformOfVendor = {
    Vendors.newApiOpenAI: newapi,
    Vendors.newApiOpenAIResponses: newapi,
    Vendors.newApiGemini: newapi,
    Vendors.newApiAnthropic: newapi,
    Vendors.xaiApi: xai,
    Vendors.officialGoogle: google,
    Vendors.deepseek: deepseek,
    Vendors.minimax: minimax,
    Vendors.minimaxAnthropic: minimax,
    Vendors.dashscope: dashscope,
    Vendors.dashscopeNative: dashscope,
    Vendors.volcengineArk: ark,
    Vendors.midjourneyProxy: midjourney,
    Vendors.ollama: ollama,
    Vendors.lmStudio: lmStudio,
    Vendors.minimaxH3Base: h3Base,
  };

  /// The platform a channel is on, from its primary route's vendor and
  /// [endpoint].
  ///
  /// A vendor-specific id names its platform. The generic protocol vendors —
  /// OpenAI-compatible, Responses, Anthropic, Gemini REST, and any unknown
  /// id — are claimed by the platform whose host the endpoint is on (an
  /// official endpoint always counts as the vendor's, standard 01 §4), and
  /// by [custom] everywhere else. The platform decides labels, default paths
  /// and which routes can be added; what goes on the wire stays with the
  /// route's vendor, so a generic vendor on a recognized host sends nothing
  /// it did not send before.
  static PlatformProfile inferPlatform(String vendorId, String endpoint) {
    final named = _platformOfVendor[vendorId];
    if (named != null) return byId(named);
    final host = hostNameOf(endpoint);
    if (host.isNotEmpty) {
      for (final p in all) {
        if (p.matchesHost(host)) return p;
      }
    }
    return byId(custom);
  }

  /// The lower-case host name of [endpoint], or '' when it is not a URL.
  static String hostNameOf(String endpoint) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || !uri.hasScheme) return '';
    return uri.host.toLowerCase();
  }

  /// The vendor that serves [kind] on a channel led by [primaryVendorId].
  ///
  /// A face the primary vendor already offers stays with it — that is the
  /// vendor and pin a model reached that face through before routes existed,
  /// so every migrated route resolves exactly as its request did. Only a
  /// face the primary vendor never offered takes the platform's own vendor
  /// for it; a face the platform does not offer either resolves to null.
  static String? routeVendor(
    PlatformProfile platform,
    String primaryVendorId,
    RouteKind kind,
  ) {
    final primary = Vendors.byId(primaryVendorId);
    if (primary.menuFor(Surface.chat).contains(kind.face)) {
      return primaryVendorId;
    }
    return platform.route(kind)?.vendorId;
  }

  /// The routes a legacy channel of [vendorId] reached before routes
  /// existed: every chat face its vendor offered, default first.
  static List<RouteKind> legacyKinds(String vendorId) => [
    for (final face in Vendors.byId(vendorId).menuFor(Surface.chat))
      ?RouteKind.ofFace(face),
  ];
}
