import '../../models/llm_channel.dart';
import '../../models/llm_model.dart';
import '../llm/channel_routes.dart';
import '../llm/model_routes.dart';
import '../llm/vendors/platforms.dart';
import 'route_switching.dart';

/// One merge the models page can offer: [keep] absorbs [absorb]. Detected
/// only — nothing merges until the user has seen [plan] and confirmed
/// (standard 04 §1).
class MergeCandidate {
  final LLMChannel keep;
  final LLMChannel absorb;
  final MergePlan plan;

  const MergeCandidate(this.keep, this.absorb, this.plan);
}

/// What merging one channel into another writes, computed without touching
/// storage (standard 04 §3). The executor applies it in the order its
/// fields are listed.
class MergePlan {
  /// The kept channel with the absorbed channel's routes appended, already
  /// normalized: its flat columns are its (unchanged) primary route.
  final LLMChannel channel;

  /// The absorbed channel's routes, now on [channel], in its order.
  final List<RouteKind> addedRoutes;

  /// Models to write: the kept channel's models that took parameters over
  /// or had to be pinned, and the absorbed channel's models moved across.
  final List<LLMModel> updates;

  /// The absorbed channel's models merged into a same-named model on the
  /// kept channel — deleted, every reference rewritten through [idMap].
  final List<int> deletes;

  /// Deleted model id → the id of the model it merged into.
  final Map<int, int> idMap;

  /// How many of the absorbed channel's models move across unchanged.
  final int movedCount;

  /// The channel deleted last.
  final int absorbedChannelId;

  const MergePlan({
    required this.channel,
    required this.addedRoutes,
    required this.updates,
    required this.deletes,
    required this.idMap,
    required this.movedCount,
    required this.absorbedChannelId,
  });

  int get mergedCount => deletes.length;
}

/// Detecting channels that are one credential split by protocol, and
/// planning their merge. Pure.
///
/// Merging is the one operation that makes a model id disappear, so it is
/// held to the standard of a delete — and to migration's rule that no
/// request changes: a pair is offered only when every route and every model
/// that survives it would resolve to the same vendor and address as before.
class ChannelMerge {
  ChannelMerge._();

  /// The merges to offer, over [channels] in rail order. Each channel is in
  /// at most one candidate, so two offers never fight over one record; the
  /// channel earlier in the rail is kept when either could be.
  ///
  /// Keys are compared in memory only and never leave this function.
  static List<MergeCandidate> candidates(
    List<LLMChannel> channels,
    List<LLMModel> models,
  ) {
    final routes = {
      for (final c in channels)
        if (c.id != null) c.id!: RoutedChannel.routesOf(c),
    };
    final used = <int>{};
    final found = <MergeCandidate>[];
    for (var i = 0; i < channels.length; i++) {
      final a = channels[i];
      if (a.id == null || used.contains(a.id)) continue;
      for (var j = i + 1; j < channels.length; j++) {
        final b = channels[j];
        if (b.id == null || used.contains(b.id)) continue;
        if (!_samePlace(a, routes[a.id]!, b, routes[b.id]!)) continue;
        final forward = plan(a, b, models);
        final chosen = forward != null
            ? MergeCandidate(a, b, forward)
            : _reverse(a, b, models);
        if (chosen == null) continue;
        found.add(chosen);
        used
          ..add(a.id!)
          ..add(b.id!);
        break;
      }
    }
    return found;
  }

  static MergeCandidate? _reverse(
    LLMChannel a,
    LLMChannel b,
    List<LLMModel> models,
  ) {
    final backward = plan(b, a, models);
    return backward == null ? null : MergeCandidate(b, a, backward);
  }

  /// Same platform, same real host, same key, disjoint routes (standard 04
  /// §2). An empty key pairs only with an empty key on the same host — two
  /// local servers at one address are one server — and a channel with no
  /// host pairs with nothing.
  static bool _samePlace(
    LLMChannel a,
    ChannelRoutes ra,
    LLMChannel b,
    ChannelRoutes rb,
  ) {
    if (ra.platform.id != rb.platform.id) return false;
    final host = _hostKey(ra.host);
    if (host.isEmpty || host != _hostKey(rb.host)) return false;
    // Byte for byte: the kept key is what the absorbed routes send.
    if (a.apiKey != b.apiKey) return false;
    return !ra.kinds.any(rb.has);
  }

  static String _hostKey(String host) {
    var h = host.trim().toLowerCase();
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  /// [absorb] merged into [keep], or null when the merge would change a
  /// request — a route whose vendor or address would differ once it serves
  /// under [keep]'s primary vendor, or an image / video model with no
  /// namesake on [keep] (those always ride the primary route, so moving one
  /// would send it somewhere else).
  static MergePlan? plan(
    LLMChannel keep,
    LLMChannel absorb,
    List<LLMModel> models,
  ) {
    final keepId = keep.id;
    final absorbId = absorb.id;
    if (keepId == null || absorbId == null || keepId == absorbId) return null;
    final kr = RoutedChannel.routesOf(keep);
    final ar = RoutedChannel.routesOf(absorb);
    if (ar.kinds.any(kr.has)) return null;

    final merged = _mergedRoutes(kr, ar);
    if (merged == null) return null;
    final channel = keep.withRoutes(
      type: merged.primaryVendorId,
      endpoint: merged.primaryAddress,
      routes: merged.encode(),
    );

    final keepModels = [
      for (final m in models)
        if (m.channelId == keepId) m,
    ];
    final absorbModels = [
      for (final m in models)
        if (m.channelId == absorbId) m,
    ];

    // The kept channel's own models, as they will be written; a model is in
    // [updates] only when it changed.
    final kept = <int, LLMModel>{
      for (final k in keepModels)
        if (k.id != null) k.id!: _pinned(k, kr, merged),
    };
    final changed = <int>{
      for (final k in keepModels)
        if (k.id != null && !identical(kept[k.id], k)) k.id!,
    };

    final taken = <int>{};
    final moved = <LLMModel>[];
    final deletes = <int>[];
    final idMap = <int, int>{};

    for (final m in absorbModels) {
      final mId = m.id;
      if (mId == null) continue;
      final twin = _namesake(m, keepModels, taken);
      if (twin != null) {
        taken.add(twin.id!);
        final into = kept[twin.id!]!;
        final carried = _carry(m, ar, into, merged);
        if (!identical(carried, into)) {
          kept[twin.id!] = carried;
          changed.add(twin.id!);
        }
        deletes.add(mId);
        idMap[mId] = twin.id!;
        continue;
      }
      final across = _moved(m, ar, merged, keepId);
      if (!_sameRequest(absorb, m, channel, across)) return null;
      moved.add(across);
    }

    return MergePlan(
      channel: channel,
      addedRoutes: ar.kinds,
      updates: [
        for (final k in keepModels)
          if (changed.contains(k.id)) kept[k.id]!,
        ...moved,
      ],
      deletes: deletes,
      idMap: idMap,
      movedCount: moved.length,
      absorbedChannelId: absorbId,
    );
  }

  /// [kr] with [ar]'s routes appended, or null when any route would resolve
  /// to a different vendor or address afterwards. An absorbed route keeps
  /// its path when both channels spell the host the same way, and becomes
  /// its full address otherwise, so not a byte of it changes.
  static ChannelRoutes? _mergedRoutes(ChannelRoutes kr, ChannelRoutes ar) {
    var merged = kr;
    for (final e in ar.entries) {
      merged = merged.withRoute(e.kind).withPath(
        e.kind,
        ar.host == kr.host ? e.path : ar.addressOf(e.kind),
      );
    }
    bool same(ChannelRoutes from, RouteKind k) =>
        merged.has(k) &&
        merged.vendorOf(k) == from.vendorOf(k) &&
        merged.addressOf(k) == from.addressOf(k);
    if (merged.primary.kind != kr.primary.kind) return null;
    if (!kr.kinds.every((k) => same(kr, k))) return null;
    if (!ar.kinds.every((k) => same(ar, k))) return null;
    return merged;
  }

  /// A model on the kept channel that [m] merges into: the same upstream
  /// model and type, not already claimed by another absorbed model.
  static LLMModel? _namesake(
    LLMModel m,
    List<LLMModel> keepModels,
    Set<int> taken,
  ) {
    for (final k in keepModels) {
      if (k.id == null || taken.contains(k.id)) continue;
      if (k.modelId == m.modelId && k.tag == m.tag) return k;
    }
    return null;
  }

  /// A kept model as it must be written so its request survives the new
  /// routes: one that followed the primary through a legacy pin the channel
  /// did not offer would now find that pin offered and quietly move — it is
  /// pinned to the route it rides instead. Unchanged models are returned as
  /// themselves.
  static LLMModel _pinned(
    LLMModel k,
    ChannelRoutes before,
    ChannelRoutes after,
  ) {
    if (!ModelRoutes.usesRoutes(k)) return k;
    final was = ModelRoutes.requestRoute(k, before);
    if (was == null || ModelRoutes.requestRoute(k, after) == was) return k;
    return k.withRouteState(
      activeRoute: was.id,
      routeParams: k.routeParams,
      wireProtocol: k.wireProtocol,
      maxOutputTokens: k.maxOutputTokens,
      enableThinking: k.enableThinking,
      reasoningEffort: k.reasoningEffort,
    );
  }

  /// [into] with [m]'s parameters for the absorbed routes parked under
  /// those routes — [m]'s current route and whatever it had parked there.
  /// What [into] already has for a route wins; its id and its own fields are
  /// kept. Image and video models have no route parameters to carry.
  static LLMModel _carry(
    LLMModel m,
    ChannelRoutes ar,
    LLMModel into,
    ChannelRoutes merged,
  ) {
    if (!ModelRoutes.usesRoutes(m) || !ModelRoutes.usesRoutes(into)) {
      return into;
    }
    final incoming = <RouteKind, RouteParams>{
      for (final e in ModelRoutes.parked(m).entries)
        if (ar.has(e.key)) e.key: e.value,
    };
    final current = ModelRoutes.requestRoute(m, ar);
    if (current != null) incoming[current] = RouteParams.ofModel(m);

    final own = ModelRoutes.displayRoute(into, merged);
    final parked = {...ModelRoutes.parked(into)};
    var added = false;
    for (final e in incoming.entries) {
      if (e.key == own || parked.containsKey(e.key)) continue;
      final params = RouteSwitching.forRoute(
        e.value,
        RouteSwitching.ladderFor(into, merged, e.key),
      );
      if (params.isEmpty) continue;
      parked[e.key] = params;
      added = true;
    }
    if (!added) return into;
    return into.withRouteState(
      activeRoute: into.activeRoute,
      routeParams: ModelRoutes.encodeParked(parked),
      wireProtocol: into.wireProtocol,
      maxOutputTokens: into.maxOutputTokens,
      enableThinking: into.enableThinking,
      reasoningEffort: into.reasoningEffort,
    );
  }

  /// [m] moved to the kept channel, its route written explicitly — the
  /// kept channel's primary is another route, and [m] must not follow it.
  static LLMModel _moved(
    LLMModel m,
    ChannelRoutes ar,
    ChannelRoutes merged,
    int keepId,
  ) {
    final across = m.movedTo(keepId);
    if (!ModelRoutes.usesRoutes(m)) return across;
    final route = ModelRoutes.requestRoute(m, ar);
    // A route already gone keeps failing until the user chooses.
    if (route == null) return across;
    return across.withRouteState(
      activeRoute: route.id,
      routeParams: m.routeParams,
      wireProtocol: RouteSwitching.compatWireProtocol(merged, route),
      maxOutputTokens: m.maxOutputTokens,
      enableThinking: m.enableThinking,
      reasoningEffort: m.reasoningEffort,
    );
  }

  /// Whether [to] on [toChannel] is sent exactly as [from] was on
  /// [fromChannel]: same route, vendor and address — for a chat model the
  /// route fixes the face — and for an image or video model the same media
  /// selection. A model whose route was already gone had no request to keep.
  static bool _sameRequest(
    LLMChannel fromChannel,
    LLMModel from,
    LLMChannel toChannel,
    LLMModel to,
  ) {
    final before = RoutedChannel.forModel(fromChannel, from);
    final after = RoutedChannel.forModel(toChannel, to);
    if (before.missing) return true;
    return !after.missing &&
        after.route == before.route &&
        after.channelType == before.channelType &&
        after.endpoint == before.endpoint &&
        (ModelRoutes.usesRoutes(from) ||
            after.wireProtocol == before.wireProtocol);
  }
}
