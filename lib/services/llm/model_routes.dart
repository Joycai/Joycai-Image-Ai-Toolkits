import 'dart:convert';

import '../../models/llm_model.dart';
import 'channel_routes.dart';
import 'llm_dispatcher.dart';
import 'vendors/platforms.dart';
import 'vendors/vendors.dart';

/// The parameters that belong to a (model, route) pair rather than to the
/// model — the one list switching and saving both act on (standard 03 §1–2).
///
/// Only three, each with evidence that the same model on the same channel
/// needs a different value per wire: the reasoning ladder differs per face
/// (`LLMDispatcher.reasoningLadder`), the thinking switch is read by ④ alone
/// in a per-face dialect, and the output cap is required on ④ but optional
/// elsewhere, under a per-vendor field name. Web search is *not* here: it is
/// the user's grant, kept on the model and checked per route at send time.
class RouteParams {
  final int? maxOutputTokens;
  final bool enableThinking;
  final String? reasoningEffort;

  const RouteParams({
    this.maxOutputTokens,
    this.enableThinking = false,
    this.reasoningEffort,
  });

  /// Never configured: nothing is sent.
  static const RouteParams empty = RouteParams();

  factory RouteParams.ofModel(LLMModel model) => RouteParams(
        maxOutputTokens: model.maxOutputTokens,
        enableThinking: model.enableThinking,
        reasoningEffort: model.reasoningEffort,
      );

  bool get isEmpty =>
      maxOutputTokens == null && !enableThinking && reasoningEffort == null;

  Map<String, Object> toJson() => {
        'max_output_tokens': ?maxOutputTokens,
        if (enableThinking) 'enable_thinking': true,
        'reasoning_effort': ?reasoningEffort,
      };

  /// Field by field; a malformed value reads as unset, never as something
  /// to send.
  static RouteParams fromJson(Object? json) {
    if (json is! Map) return empty;
    final cap = json['max_output_tokens'];
    final effort = json['reasoning_effort'];
    return RouteParams(
      maxOutputTokens: cap is int && cap > 0 ? cap : null,
      enableThinking: json['enable_thinking'] == true,
      reasoningEffort: effort is String && effort.isNotEmpty ? effort : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RouteParams &&
      other.maxOutputTokens == maxOutputTokens &&
      other.enableThinking == enableThinking &&
      other.reasoningEffort == reasoningEffort;

  @override
  int get hashCode => Object.hash(maxOutputTokens, enableThinking, reasoningEffort);

  @override
  String toString() =>
      'RouteParams(cap: $maxOutputTokens, thinking: $enableThinking, effort: $reasoningEffort)';
}

/// How a stored model sits on its channel's routes. Pure; reads the raw
/// `active_route` / `route_params` / `wire_protocol` columns.
class ModelRoutes {
  ModelRoutes._();

  /// Whether [model] rides a route at all: chat-surface models do, image and
  /// video models pick a dedicated endpoint instead.
  static bool usesRoutes(LLMModel model) =>
      LLMDispatcher.surfaceForModel(model.modelId, tag: model.tag) ==
      Surface.chat;

  /// The parameters parked for [model]'s other routes, by route.
  static Map<RouteKind, RouteParams> parked(LLMModel model) {
    final raw = model.routeParams;
    if (raw == null || raw.trim().isEmpty) return const {};
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return const {};
    }
    if (json is! Map) return const {};
    return {
      for (final entry in json.entries)
        ?RouteKind.tryParse(entry.key as String?):
            RouteParams.fromJson(entry.value),
    };
  }

  /// [parked] as the `route_params` column, or null when there is nothing.
  static String? encodeParked(Map<RouteKind, RouteParams> parked) {
    if (parked.isEmpty) return null;
    return jsonEncode({
      for (final e in parked.entries) e.key.id: e.value.toJson(),
    });
  }

  /// The route [model] chose explicitly: its `active_route`, else — for a row
  /// written before routes — the chat face its `wire_protocol` pinned. Null
  /// means "follow the primary route".
  static RouteKind? explicitRoute(LLMModel model) {
    if (!usesRoutes(model)) return null;
    final stored = RouteKind.tryParse(model.activeRoute);
    if (stored != null) return stored;
    final pin = WireProtocol.tryParse(model.wireProtocol);
    return pin == null ? null : RouteKind.ofFace(pin);
  }

  /// The route a *request* for [model] takes on [routes], or null when the
  /// model chose a route the channel no longer offers — which the resolver
  /// reports rather than quietly sending over the primary route with
  /// parameters set for another wire (standard 02 §2).
  ///
  /// A legacy pin the channel does not offer is the exception: before routes
  /// such a pin was stale and silently degraded to the channel default, so
  /// it still does — the one reading that keeps every old row's request
  /// unchanged.
  static RouteKind? requestRoute(LLMModel model, ChannelRoutes routes) {
    if (!usesRoutes(model)) return routes.primary.kind;
    final stored = RouteKind.tryParse(model.activeRoute);
    if (stored != null) return routes.has(stored) ? stored : null;
    final legacy = explicitRoute(model);
    if (legacy != null && routes.has(legacy)) return legacy;
    return routes.primary.kind;
  }

  /// The route to *show* for [model]: [requestRoute], falling back to the
  /// primary so a list or an estimate never fails on a missing route.
  static RouteKind displayRoute(LLMModel model, ChannelRoutes routes) =>
      requestRoute(model, routes) ?? routes.primary.kind;

  /// The routes [model] has enabled on [routes], its current one first: the
  /// current route plus every route with parked parameters, in the channel's
  /// order. Routes the channel offers but the model never enabled are not
  /// here — the editor shows them as "add".
  static List<RouteKind> enabledRoutes(LLMModel model, ChannelRoutes routes) {
    final current = displayRoute(model, routes);
    final parkedKinds = parked(model).keys.toSet();
    return [
      current,
      for (final k in routes.kinds)
        if (k != current && parkedKinds.contains(k)) k,
    ];
  }
}
