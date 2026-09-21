import 'dart:convert';

import 'vendors/platforms.dart';
import 'vendors/vendors.dart';

/// One route a channel offers: a [kind] and its path override.
///
/// [path] null means the platform's default for [kind] — which follows the
/// platform table when it changes. A relative path is joined to the channel
/// host; an absolute URL replaces host and path together (a relay that puts
/// one protocol on its own subdomain). An override equal to the default is
/// stored as null, so "default" and "happens to equal the default" never
/// diverge (standard 02 §5).
class RouteEntry {
  final RouteKind kind;
  final String? path;

  const RouteEntry(this.kind, [this.path]);

  @override
  bool operator ==(Object other) =>
      other is RouteEntry && other.kind == kind && other.path == path;

  @override
  int get hashCode => Object.hash(kind, path);

  @override
  String toString() => 'RouteEntry(${kind.id}, $path)';
}

/// A channel's routes, resolved: the embedded `llm_channels.routes` document
/// read against the flat `type` / `endpoint` columns.
///
/// **The flat columns always hold the primary route** — its vendor and its
/// full address — so every reader that predates routes keeps working, and a
/// writer that only knows the flat columns (an older build, a restored older
/// backup, the first-run wizard) is detected by the write mark and folded
/// back in ([resolve]). Everything here is pure; the repository persists
/// [encode]'s output beside [primaryVendorId] and [primaryAddress].
///
/// Read-time migration: a channel with no document gets one route per chat
/// face its vendor offered — the faces a model could already pin — each at
/// the address the dispatcher derived for that face, split into host + path
/// on the raw string. The one property this has to prove is that no request
/// address changes by a byte (`test/services/llm/channel_routes_test.dart`).
class ChannelRoutes {
  /// Document version written into [encode]. A document with a higher
  /// version is still read field by field; unknown fields are ignored.
  static const int docVersion = 1;

  final PlatformProfile platform;

  /// `scheme://authority` taken verbatim from the stored address, or '' for
  /// a legacy endpoint that is not a URL (then every path is the whole
  /// address).
  final String host;

  /// In order; the first is the primary route. Never empty, one per kind.
  final List<RouteEntry> entries;

  /// The vendor serving the primary route — the flat `type` column.
  final String primaryVendorId;

  ChannelRoutes._({
    required this.platform,
    required this.host,
    required List<RouteEntry> entries,
    required this.primaryVendorId,
  }) : entries = List.unmodifiable(entries);

  RouteEntry get primary => entries.first;

  List<RouteKind> get kinds => [for (final e in entries) e.kind];

  bool has(RouteKind kind) => entry(kind) != null;

  RouteEntry? entry(RouteKind kind) {
    for (final e in entries) {
      if (e.kind == kind) return e;
    }
    return null;
  }

  /// The vendor profile id that serves [kind] on this channel, or null when
  /// the channel does not offer it.
  String? vendorOf(RouteKind kind) {
    if (!has(kind)) return null;
    if (kind == primary.kind) return primaryVendorId;
    return Platforms.routeVendor(platform, primaryVendorId, kind);
  }

  /// What [kind]'s route sends beyond the protocol's standard part — the
  /// add-channel preview's one word per route (`D1f · 4b`): the host's own
  /// web search where its vendor sends it and the platform is known to act
  /// on it ([PlatformProfile.untestedWebSearch] stays quiet), and ④'s
  /// prompt-cache breakpoints. Read off the vendor profile, never the id.
  ({bool webSearch, bool promptCaching}) featuresOf(RouteKind kind) {
    final vendorId = vendorOf(kind);
    if (vendorId == null) return (webSearch: false, promptCaching: false);
    final vendor = Vendors.byId(vendorId);
    return (
      webSearch: vendor.sendsWebSearchOn(kind.face) &&
          !platform.untestedWebSearch.contains(kind),
      promptCaching: vendor.promptCaching && kind.face == WireProtocol.anthropicChat,
    );
  }

  /// The platform default path for [kind], or null when the platform does
  /// not offer it (then the route always carries its own path).
  String? defaultPathOf(RouteKind kind) => platform.route(kind)?.defaultPath;

  /// The full base address of [kind]'s route, or null when not offered.
  String? addressOf(RouteKind kind) {
    final e = entry(kind);
    if (e == null) return null;
    return joinAddress(host, e.path ?? defaultPathOf(kind) ?? '');
  }

  String get primaryAddress => addressOf(primary.kind)!;

  /// The base address of every route, keyed by the chat wire it speaks —
  /// what the dispatcher consults before deriving a face from the endpoint.
  Map<WireProtocol, String> get faceBases => {
    for (final e in entries) e.kind.face: addressOf(e.kind)!,
  };

  static final RegExp _absolute = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
  static final RegExp _hostSplit = RegExp(
    r'^([a-zA-Z][a-zA-Z0-9+.\-]*://[^/?#]*)(.*)$',
    dotAll: true,
  );

  static bool isAbsolute(String path) => _absolute.hasMatch(path);

  /// [host] + [path], or [path] alone when it is absolute.
  static String joinAddress(String host, String path) =>
      isAbsolute(path) ? path : '$host$path';

  /// Splits [address] into `scheme://authority` and the rest, on the raw
  /// string. Never through a URL parser: it lower-cases the host and adds a
  /// trailing slash, and the address would no longer rebuild byte for byte
  /// (standard 06 §5). A non-URL yields ('', address).
  static (String, String) splitHost(String address) {
    final m = _hostSplit.firstMatch(address);
    if (m == null) return ('', address);
    return (m.group(1)!, m.group(2)!);
  }

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  /// The routes of a channel stored as ([type], [endpoint], [doc]).
  ///
  /// * No document, or one that parses to nothing usable → [legacy].
  /// * A document whose write mark no longer matches the flat columns →
  ///   someone else rewrote the channel through the flat columns alone: the
  ///   primary route is rebuilt from them and the other routes are kept —
  ///   unless the rewrite moved the channel to another platform, which
  ///   replaces it: then only the flat columns' own routes ([legacy]).
  /// * Otherwise the document, narrowed: unknown kinds, duplicate kinds and
  ///   kinds no vendor on this platform can serve are dropped.
  static ChannelRoutes resolve(String type, String endpoint, String? doc) {
    final key = '$type\u0000$endpoint\u0000${doc ?? ''}';
    final hit = _resolved[key];
    if (hit != null) return hit;
    if (_resolved.length >= 256) _resolved.clear();
    return _resolved[key] = _resolve(type, endpoint, doc);
  }

  /// [resolve] is pure and asked from build methods (a model card, the
  /// workbench's descriptor lookup), so its answers are kept per input.
  static final Map<String, ChannelRoutes> _resolved = {};

  static ChannelRoutes _resolve(String type, String endpoint, String? doc) {
    final parsed = _Doc.tryParse(doc);
    final legacyRoutes = legacy(type, endpoint);
    if (parsed == null || parsed.entries.isEmpty) return legacyRoutes;

    if (parsed.markType != type || parsed.markEndpoint != endpoint) {
      // A rewrite that moved the channel to another platform replaced it:
      // the document's routes were that platform's, and read under this one
      // they would be served by vendors and defaults nobody chose.
      final markType = parsed.markType;
      final markEndpoint = parsed.markEndpoint;
      if (markType != null &&
          markEndpoint != null &&
          Platforms.inferPlatform(markType, markEndpoint).id !=
              legacyRoutes.platform.id) {
        return legacyRoutes;
      }
      // Primary from the flat columns; the document's other routes after it,
      // then any face the flat vendor offered that neither mentions.
      final seen = <RouteKind>{legacyRoutes.primary.kind};
      final merged = <RouteEntry>[legacyRoutes.primary];
      for (final e in [...parsed.entries, ...legacyRoutes.entries.skip(1)]) {
        if (seen.add(e.kind)) merged.add(e);
      }
      return _narrowed(
            platform: legacyRoutes.platform,
            host: legacyRoutes.host,
            entries: merged,
            primaryVendorId: type,
          ) ??
          legacyRoutes;
    }

    return _narrowed(
          platform: Platforms.inferPlatform(type, endpoint),
          host: parsed.host,
          entries: parsed.entries,
          primaryVendorId: type,
        ) ??
        legacyRoutes;
  }

  /// [entries] less duplicates, kinds no vendor here serves, and default-path
  /// routes the platform has no default for; null when nothing is left.
  static ChannelRoutes? _narrowed({
    required PlatformProfile platform,
    required String host,
    required List<RouteEntry> entries,
    required String primaryVendorId,
  }) {
    final seen = <RouteKind>{};
    final kept = <RouteEntry>[];
    for (final e in entries) {
      if (!seen.add(e.kind)) continue;
      final servable =
          kept.isEmpty ||
          Platforms.routeVendor(platform, primaryVendorId, e.kind) != null;
      // A route with no path of its own needs the platform's default.
      final addressable = e.path != null || platform.offers(e.kind);
      if (servable && addressable) kept.add(e);
    }
    if (kept.isEmpty) return null;
    return ChannelRoutes._(
      platform: platform,
      host: host,
      entries: kept,
      primaryVendorId: primaryVendorId,
    );
  }

  /// The routes a channel had before routes existed: one per chat face its
  /// vendor offered, each at the address the dispatcher derived for it.
  static ChannelRoutes legacy(String type, String endpoint) {
    final vendor = Vendors.byId(type);
    final platform = Platforms.inferPlatform(type, endpoint);
    final (host, _) = splitHost(endpoint);
    final entries = <RouteEntry>[];
    for (final kind in Platforms.legacyKinds(type)) {
      final derive = vendor.protocolBases[kind.face];
      final address = derive == null ? endpoint : derive(endpoint);
      entries.add(RouteEntry(kind, _pathFor(platform, host, kind, address)));
    }
    return ChannelRoutes._(
      platform: platform,
      host: host,
      entries: entries,
      primaryVendorId: type,
    );
  }

  /// The path to store so that `host + path` (or the default) rebuilds
  /// [address] exactly.
  static String? _pathFor(
    PlatformProfile platform,
    String host,
    RouteKind kind,
    String address,
  ) {
    if (host.isEmpty || !address.startsWith(host)) return address;
    final rest = address.substring(host.length);
    return rest == platform.route(kind)?.defaultPath ? null : rest;
  }

  // ---------------------------------------------------------------------------
  // Building and editing
  // ---------------------------------------------------------------------------

  /// A new channel on [platform] at [host] with [kinds] (primary first).
  static ChannelRoutes create(
    PlatformProfile platform,
    String host,
    List<RouteKind> kinds, {
    Map<RouteKind, String> paths = const {},
  }) {
    assert(kinds.isNotEmpty);
    final primaryKind = kinds.first;
    final vendor = platform.route(primaryKind)?.vendorId ?? Vendors.openAIRest;
    return _narrowed(
      platform: platform,
      host: host,
      entries: [
        for (final k in kinds)
          RouteEntry(k, _normalizedPath(platform, k, paths[k])),
      ],
      primaryVendorId: vendor,
    )!;
  }

  static String? _normalizedPath(
    PlatformProfile platform,
    RouteKind kind,
    String? path,
  ) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed == platform.route(kind)?.defaultPath) return null;
    return trimmed;
  }

  ChannelRoutes _copy({
    String? host,
    List<RouteEntry>? entries,
    String? primaryVendorId,
  }) =>
      _narrowed(
        platform: platform,
        host: host ?? this.host,
        entries: entries ?? this.entries,
        primaryVendorId: primaryVendorId ?? this.primaryVendorId,
      ) ??
      this;

  ChannelRoutes withHost(String host) => _copy(host: host.trim());

  /// [kind]'s path set to [path]; null or the default restores the default.
  ChannelRoutes withPath(RouteKind kind, String? path) => _copy(
    entries: [
      for (final e in entries)
        e.kind == kind
            ? RouteEntry(kind, _normalizedPath(platform, kind, path))
            : e,
    ],
  );

  /// [kind] enabled at the platform default, appended after the others.
  ChannelRoutes withRoute(RouteKind kind) =>
      has(kind) ? this : _copy(entries: [...entries, RouteEntry(kind)]);

  /// [kind] removed. The primary route and the only route cannot be removed
  /// here — the caller also refuses a route a model is using.
  ChannelRoutes withoutRoute(RouteKind kind) {
    if (entries.length <= 1 || kind == primary.kind) return this;
    return _copy(
      entries: [
        for (final e in entries)
          if (e.kind != kind) e,
      ],
    );
  }

  /// [kind] made the primary route. Its vendor becomes the platform's vendor
  /// for that route when the platform names one, else the one that already
  /// served it here.
  ChannelRoutes withPrimary(RouteKind kind) {
    if (!has(kind) || kind == primary.kind) return this;
    final vendor = platform.route(kind)?.vendorId ?? vendorOf(kind)!;
    return _copy(
      entries: [
        entry(kind)!,
        for (final e in entries)
          if (e.kind != kind) e,
      ],
      primaryVendorId: vendor,
    );
  }

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  /// The document for `llm_channels.routes`, carrying the write mark: the
  /// flat values it is written beside.
  String encode() => jsonEncode({
    'v': docVersion,
    'host': host,
    'routes': [
      for (final e in entries)
        {'kind': e.kind.id, if (e.path != null) 'path': e.path},
    ],
    'mark': {'type': primaryVendorId, 'endpoint': primaryAddress},
  });
}

/// The stored document, parsed field by field. Anything malformed reads as
/// absent rather than as a value to send (standard 02 §1).
class _Doc {
  final String host;
  final List<RouteEntry> entries;
  final String? markType;
  final String? markEndpoint;

  _Doc(this.host, this.entries, this.markType, this.markEndpoint);

  static _Doc? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final host = json['host'];
    final routes = json['routes'];
    if (host is! String || routes is! List) return null;
    final entries = <RouteEntry>[];
    for (final r in routes) {
      if (r is! Map) continue;
      final rawKind = r['kind'];
      final kind = RouteKind.tryParse(rawKind is String ? rawKind : null);
      if (kind == null) continue;
      final path = r['path'];
      entries.add(RouteEntry(kind, path is String ? path : null));
    }
    final mark = json['mark'];
    return _Doc(
      host,
      entries,
      mark is Map && mark['type'] is String ? mark['type'] as String : null,
      mark is Map && mark['endpoint'] is String
          ? mark['endpoint'] as String
          : null,
    );
  }
}
