import '../../models/llm_model.dart';
import '../llm/channel_routes.dart';
import '../llm/llm_dispatcher.dart';
import '../llm/llm_model_config.dart';
import '../llm/model_routes.dart';
import '../llm/vendors/platforms.dart';
import '../llm/vendors/vendors.dart';

/// One per-route parameter as it changes when a model moves route — a row of
/// the editor's switch preview (`D1f · 4d`). A null side is "not set, not
/// sent".
class RouteParamChange {
  final RouteParamField field;
  final Object? from;
  final Object? to;

  const RouteParamChange(this.field, this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is RouteParamChange && other.field == field && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(field, from, to);

  @override
  String toString() => 'RouteParamChange($field: $from → $to)';
}

enum RouteParamField { reasoningEffort, thinking, maxOutputTokens }

/// Moving a model between its channel's routes, and the one rule that both
/// switching and saving apply to per-route parameters (standard 03 §1–2,
/// §4). Pure: every function answers a new [LLMModel]; the caller persists.
class RouteSwitching {
  RouteSwitching._();

  /// The reasoning rungs [model] has on [kind] — the ladder of the face that
  /// route speaks, through the vendor that serves it on this channel.
  static List<ReasoningEffort?> ladderFor(LLMModel model, ChannelRoutes routes, RouteKind kind) {
    final vendorId = routes.vendorOf(kind) ?? routes.primaryVendorId;
    return LLMDispatcher.reasoningLadder(
      channelType: vendorId,
      modelId: model.modelId,
      tag: model.tag,
      wireProtocol: kind.face.id,
    );
  }

  /// [params] with everything the route cannot say removed — **the** rule,
  /// applied when saving the current route and when parking or loading one.
  ///
  /// * A reasoning effort not on the route's ladder is replaced by the rung
  ///   that sends the same request there — the highest rung at or below it,
  ///   else the lowest above it (a boolean switch sends any "on" as its one
  ///   on rung; Gemini sends Max as the top of its scale). Off, and any
  ///   effort on a route with no "on" rung at all, becomes unset: there it
  ///   reaches the wire as nothing.
  /// * The legacy thinking flag follows the effort, exactly as the editor has
  ///   always written it (on for any effort but Off), so the flag can never
  ///   outlive the effort it stood for.
  /// * The output cap is kept when positive: every chat face has one.
  static RouteParams forRoute(RouteParams params, List<ReasoningEffort?> ladder) {
    // The legacy flag alone means Medium — `effectiveReasoningEffort`.
    final effort =
        ReasoningEffort.tryParse(params.reasoningEffort) ??
        (params.enableThinking ? ReasoningEffort.medium : null);
    final kept = _onLadder(effort, ladder);
    final cap = params.maxOutputTokens;
    return RouteParams(
      maxOutputTokens: cap != null && cap > 0 ? cap : null,
      reasoningEffort: kept?.name,
      enableThinking: kept != null && kept != ReasoningEffort.off,
    );
  }

  static ReasoningEffort? _onLadder(ReasoningEffort? effort, List<ReasoningEffort?> ladder) {
    if (effort == null) return null;
    if (ladder.contains(effort)) return effort;
    if (effort == ReasoningEffort.off) return null;
    final on = [
      for (final r in ladder)
        if (r != null && r != ReasoningEffort.off) r,
    ]..sort((a, b) => a.index.compareTo(b.index));
    if (on.isEmpty) return null;
    final below = on.where((r) => r.index <= effort.index);
    return below.isNotEmpty ? below.last : on.first;
  }

  /// The `wire_protocol` a chat model on [kind] keeps for builds that
  /// predate routes: the face itself when the primary vendor offers it (an
  /// older build then routes the model exactly as this one does), else null
  /// — an older build cannot reach that route and sends the model over its
  /// channel's default, the known gap of standard 02 §4.
  static String? compatWireProtocol(ChannelRoutes routes, RouteKind kind) {
    final menu = Vendors.byId(routes.primaryVendorId).menuFor(Surface.chat);
    return menu.contains(kind.face) ? kind.face.id : null;
  }

  /// [model] saved on its current route: the shared rule applied to its flat
  /// per-route fields, the route written explicitly. Media models pass
  /// through untouched.
  static LLMModel normalizedForSave(LLMModel model, ChannelRoutes routes) {
    if (!ModelRoutes.usesRoutes(model)) return model;
    final kind = ModelRoutes.displayRoute(model, routes);
    final params = forRoute(RouteParams.ofModel(model), ladderFor(model, routes, kind));
    final parked = {...ModelRoutes.parked(model)}..remove(kind);
    return model.withRouteState(
      activeRoute: kind.id,
      routeParams: ModelRoutes.encodeParked(parked),
      wireProtocol: compatWireProtocol(routes, kind),
      maxOutputTokens: params.maxOutputTokens,
      enableThinking: params.enableThinking,
      reasoningEffort: params.reasoningEffort,
    );
  }

  /// [model] moved to route [to]: its current parameters parked under the
  /// route it leaves, [to]'s parked parameters loaded — **empty when [to]
  /// was never configured, never copied from the route being left** — and
  /// every per-route field overwritten, so nothing of the old route leaks
  /// into the new one. The model id and every model-scoped field (web
  /// search, context window, fee group…) are untouched.
  static LLMModel switchRoute(LLMModel model, ChannelRoutes routes, RouteKind to) {
    assert(ModelRoutes.usesRoutes(model));
    final from = _heldRoute(model, routes);
    if (from == to) return normalizedForSave(model, routes);
    final parked = {...ModelRoutes.parked(model)};
    parked[from] = forRoute(RouteParams.ofModel(model), ladderFor(model, routes, from));
    final loaded = forRoute(parked.remove(to) ?? RouteParams.empty, ladderFor(model, routes, to));
    return model.withRouteState(
      activeRoute: to.id,
      routeParams: ModelRoutes.encodeParked(parked),
      wireProtocol: compatWireProtocol(routes, to),
      maxOutputTokens: loaded.maxOutputTokens,
      enableThinking: loaded.enableThinking,
      reasoningEffort: loaded.reasoningEffort,
    );
  }

  /// The route [model]'s flat parameters belong to: the route it rides, or —
  /// when the route it chose is gone from the channel — that route still.
  /// Its values are parked under it rather than filed under the primary the
  /// model is merely *shown* on, which would overwrite what the primary had.
  static RouteKind _heldRoute(LLMModel model, ChannelRoutes routes) =>
      ModelRoutes.requestRoute(model, routes) ??
      ModelRoutes.explicitRoute(model) ??
      routes.primary.kind;

  /// [model] with a route that is gone from its channel moved onto the
  /// primary — its values parked under the route it chose, the primary's
  /// own parked values loaded — or [model] itself when its route is there.
  /// What the editor opens such a model as, so that what it shows under the
  /// primary are the primary's values.
  static LLMModel recoverMissingRoute(LLMModel model, ChannelRoutes routes) {
    if (!ModelRoutes.usesRoutes(model)) return model;
    if (ModelRoutes.requestRoute(model, routes) != null) return model;
    return switchRoute(model, routes, routes.primary.kind);
  }

  /// What [switchRoute] would change, for the preview shown before the user
  /// confirms. Only the fields that differ.
  static List<RouteParamChange> preview(LLMModel model, ChannelRoutes routes, RouteKind to) {
    final from = _heldRoute(model, routes);
    final before = forRoute(RouteParams.ofModel(model), ladderFor(model, routes, from));
    final after = RouteParams.ofModel(switchRoute(model, routes, to));
    return [
      if (before.reasoningEffort != after.reasoningEffort)
        RouteParamChange(
          RouteParamField.reasoningEffort,
          before.reasoningEffort,
          after.reasoningEffort,
        ),
      if (before.enableThinking != after.enableThinking)
        RouteParamChange(RouteParamField.thinking, before.enableThinking, after.enableThinking),
      if (before.maxOutputTokens != after.maxOutputTokens)
        RouteParamChange(
          RouteParamField.maxOutputTokens,
          before.maxOutputTokens,
          after.maxOutputTokens,
        ),
    ];
  }

  /// The chat models on a channel that follow its primary route without
  /// having chosen it. Before the primary changes, each must be pinned to the
  /// primary it has — otherwise it silently moves to another wire carrying
  /// parameters set for the old one (standard 06 §1).
  static List<LLMModel> pinFollowers(Iterable<LLMModel> modelsOnChannel, ChannelRoutes routes) {
    final primary = routes.primary.kind;
    bool follows(LLMModel m) {
      if (!ModelRoutes.usesRoutes(m)) return false;
      final chosen = ModelRoutes.explicitRoute(m);
      if (chosen == null) return true;
      // A legacy pin the channel does not offer follows the primary too. An
      // explicit route that is gone does not: that model must keep failing
      // until the user chooses, not be moved here quietly.
      return m.activeRoute == null && !routes.has(chosen);
    }

    return [
      for (final m in modelsOnChannel)
        if (follows(m))
          m.withRouteState(
            activeRoute: primary.id,
            routeParams: m.routeParams,
            wireProtocol: m.wireProtocol,
            maxOutputTokens: m.maxOutputTokens,
            enableThinking: m.enableThinking,
            reasoningEffort: m.reasoningEffort,
          ),
    ];
  }

  /// What a channel edit that took its routes from [before] to [after]
  /// does to [modelsOnChannel]:
  ///
  /// * [pinned] — when the primary changed but the old one is still there,
  ///   the models that followed it, pinned to it ([pinFollowers]);
  /// * [moved] — the models that rode a route the edit removed (a new
  ///   preset can drop any route, past the table's in-use guard), moved onto
  ///   the new primary with their values parked under the route they chose
  ///   ([recoverMissingRoute]) rather than left failing.
  ///
  /// A model whose route was already gone before the edit is not touched:
  /// that one is the user's to choose.
  static ({List<LLMModel> pinned, List<LLMModel> moved}) afterChannelEdit(
    Iterable<LLMModel> modelsOnChannel,
    ChannelRoutes before,
    ChannelRoutes after,
  ) {
    final oldPrimary = before.primary.kind;
    final pinned = after.primary.kind != oldPrimary && after.has(oldPrimary)
        ? pinFollowers(modelsOnChannel, before)
        : const <LLMModel>[];
    final moved = [
      for (final m in modelsOnChannel)
        if (ModelRoutes.usesRoutes(m))
          if (RouteKind.tryParse(m.activeRoute) case final chosen?)
            if (before.has(chosen) && !after.has(chosen)) recoverMissingRoute(m, after),
    ];
    return (pinned: pinned, moved: moved);
  }

  /// How many of [modelsOnChannel] ride [kind] right now — a route in use
  /// cannot be removed from the channel.
  static int modelsOnRoute(
    Iterable<LLMModel> modelsOnChannel,
    ChannelRoutes routes,
    RouteKind kind,
  ) {
    var n = 0;
    for (final m in modelsOnChannel) {
      if (ModelRoutes.usesRoutes(m) && ModelRoutes.displayRoute(m, routes) == kind) {
        n++;
      }
    }
    return n;
  }
}
