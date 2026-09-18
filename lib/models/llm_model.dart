class LLMModel {
  final int? id;
  final String modelId;
  final String modelName;
  /// The model's kind: `chat`, `image`, `video`, `multimodal` (or the legacy
  /// `refiner`). Written by `inferTag` at discovery and editable by the user.
  ///
  /// Not only a picker filter: it is the user's declaration of which surface
  /// the model is on, and the dispatcher routes by it — which protocol menu
  /// the model gets, and so which `wireProtocol` selections are valid. That is
  /// what lets a relay model whose free-text name classifies as nothing be
  /// sent to the image or video surface at all.
  final String tag;
  final bool isPaid;
  final bool supportsStream;
  final bool supportsStandard;
  final int sortOrder;
  final int? channelId;
  final int? feeGroupId;

  /// Maximum context window (in tokens) the model supports. Used to size
  /// batched requests — e.g. how many candidate images the image downloader
  /// shows the model per call. Null means "unknown"; callers fall back to a
  /// conservative default.
  final int? contextWindow;

  /// The output cap sent with every chat request, in tokens, or null to send
  /// none. Null is the common state: ①②③ then leave the field off and the
  /// host applies its own default, ④ substitutes its built-in constant. A
  /// positive number goes out as the wire's spelling of the cap (see
  /// `outputCapFor` in the protocol layer). There is no "unlimited" value —
  /// on the families where the cap is optional, unlimited *is* null.
  final int? maxOutputTokens;

  /// When true, agent workflows (prompt optimizer) instruct the model that it
  /// MUST view every reference image before delivering a result. Meant for
  /// small local models that otherwise look at one image and stop.
  final bool forceViewAllImages;

  /// Ask the model to reason before answering (④ only, off by default).
  ///
  /// Per model rather than per channel: one Anthropic-format channel serves
  /// models that support thinking and models that reject the parameter, and
  /// the spelling it goes out in is the channel's business (see
  /// [ThinkingDialect]), not this flag's.
  final bool enableThinking;

  /// Stored `ReasoningEffort` name, or null for default. Raw string here —
  /// the LLM layer parses it; keeping the model row dumb means an unknown
  /// name from a newer build survives a round-trip instead of being dropped.
  final String? reasoningEffort;

  /// Let the host run web searches on its own during a turn (④ only, off by
  /// default). Costs tokens and reaches the network on the user's behalf, so
  /// it never turns itself on.
  final bool enableWebSearch;

  /// Explicit wire-protocol selection (`WireProtocol.id` string), or null for
  /// auto — the overwhelmingly common state. Raw string here for the same
  /// reason as [reasoningEffort]: the LLM layer parses and validates it, so
  /// an unknown value from a newer build survives a round-trip, and one
  /// stranded by a channel-type change degrades to auto instead of failing.
  final String? wireProtocol;

  /// The route a chat model rides (`RouteKind.id`, v45), or null to follow
  /// the channel's primary route. Raw for the same reason as [wireProtocol].
  ///
  /// A row written before routes existed has null here and its chat face in
  /// [wireProtocol]; the LLM layer reads that pin as the route, so nothing
  /// needs rewriting. Image and video models have no route — their
  /// [wireProtocol] keeps selecting the media endpoint.
  final String? activeRoute;

  /// The per-route parameters parked for this model's *other* routes, as a
  /// JSON object keyed by route id (v45). The flat [maxOutputTokens],
  /// [enableThinking] and [reasoningEffort] are always the active route's;
  /// switching routes parks them here and loads the target's. A key with an
  /// empty object is a route the model has enabled but never configured.
  final String? routeParams;

  // Performance metrics
  final double? estMeanMs;
  final double? estSdMs;
  final int tasksSinceUpdate;

  LLMModel({
    this.id,
    required this.modelId,
    required this.modelName,
    required this.tag,
    this.isPaid = true,
    this.supportsStream = true,
    this.supportsStandard = true,
    this.sortOrder = 0,
    this.channelId,
    this.feeGroupId,
    this.contextWindow,
    this.maxOutputTokens,
    this.forceViewAllImages = false,
    this.enableThinking = false,
    this.reasoningEffort,
    this.enableWebSearch = false,
    this.wireProtocol,
    this.activeRoute,
    this.routeParams,
    this.estMeanMs,
    this.estSdMs,
    this.tasksSinceUpdate = 0,
  });

  factory LLMModel.fromMap(Map<String, dynamic> map) {
    return LLMModel(
      id: map['id'] as int?,
      modelId: map['model_id'] as String,
      modelName: map['model_name'] as String,
      tag: map['tag'] as String,
      isPaid: (map['is_paid'] ?? 1) == 1,
      supportsStream: (map['supports_stream'] ?? 1) == 1,
      supportsStandard: (map['supports_standard'] ?? 1) == 1,
      sortOrder: map['sort_order'] as int? ?? 0,
      channelId: map['channel_id'] as int?,
      feeGroupId: map['fee_group_id'] as int?,
      contextWindow: map['context_window'] as int?,
      maxOutputTokens: map['max_output_tokens'] as int?,
      forceViewAllImages: (map['force_view_all_images'] ?? 0) == 1,
      enableThinking: (map['enable_thinking'] ?? 0) == 1,
      reasoningEffort: map['reasoning_effort'] as String?,
      enableWebSearch: (map['enable_web_search'] ?? 0) == 1,
      wireProtocol: map['wire_protocol'] as String?,
      activeRoute: map['active_route'] as String?,
      routeParams: map['route_params'] as String?,
      estMeanMs: map['est_mean_ms'] as double?,
      estSdMs: map['est_sd_ms'] as double?,
      tasksSinceUpdate: map['tasks_since_update'] as int? ?? 0,
    );
  }

  /// This model with every route-dependent field replaced at once — the flat
  /// per-route parameters, the route selection and the parked parameters.
  /// All required so that a null is a value, not "unchanged": switching to a
  /// route that was never configured must clear, not keep (standard 03 §1).
  LLMModel withRouteState({
    required String? activeRoute,
    required String? routeParams,
    required String? wireProtocol,
    required int? maxOutputTokens,
    required bool enableThinking,
    required String? reasoningEffort,
  }) =>
      LLMModel(
        id: id,
        modelId: modelId,
        modelName: modelName,
        tag: tag,
        isPaid: isPaid,
        supportsStream: supportsStream,
        supportsStandard: supportsStandard,
        sortOrder: sortOrder,
        channelId: channelId,
        feeGroupId: feeGroupId,
        contextWindow: contextWindow,
        maxOutputTokens: maxOutputTokens,
        forceViewAllImages: forceViewAllImages,
        enableThinking: enableThinking,
        reasoningEffort: reasoningEffort,
        enableWebSearch: enableWebSearch,
        wireProtocol: wireProtocol,
        activeRoute: activeRoute,
        routeParams: routeParams,
        estMeanMs: estMeanMs,
        estSdMs: estSdMs,
        tasksSinceUpdate: tasksSinceUpdate,
      );

  /// This model moved to channel [channelId] — a channel merge's one change
  /// of ownership. Everything else, the id included, is kept.
  LLMModel movedTo(int channelId) => LLMModel(
    id: id,
    modelId: modelId,
    modelName: modelName,
    tag: tag,
    isPaid: isPaid,
    supportsStream: supportsStream,
    supportsStandard: supportsStandard,
    sortOrder: sortOrder,
    channelId: channelId,
    feeGroupId: feeGroupId,
    contextWindow: contextWindow,
    maxOutputTokens: maxOutputTokens,
    forceViewAllImages: forceViewAllImages,
    enableThinking: enableThinking,
    reasoningEffort: reasoningEffort,
    enableWebSearch: enableWebSearch,
    wireProtocol: wireProtocol,
    activeRoute: activeRoute,
    routeParams: routeParams,
    estMeanMs: estMeanMs,
    estSdMs: estSdMs,
    tasksSinceUpdate: tasksSinceUpdate,
  );

  Map<String, dynamic> toMap({bool includeId = true}) {
    final map = {
      'model_id': modelId,
      'model_name': modelName,
      'tag': tag,
      'is_paid': isPaid ? 1 : 0,
      'supports_stream': supportsStream ? 1 : 0,
      'supports_standard': supportsStandard ? 1 : 0,
      'sort_order': sortOrder,
      'channel_id': channelId,
      'fee_group_id': feeGroupId,
      'context_window': contextWindow,
      'max_output_tokens': maxOutputTokens,
      'force_view_all_images': forceViewAllImages ? 1 : 0,
      'enable_thinking': enableThinking ? 1 : 0,
      'reasoning_effort': reasoningEffort,
      'enable_web_search': enableWebSearch ? 1 : 0,
      'wire_protocol': wireProtocol,
      'active_route': activeRoute,
      'route_params': routeParams,
      'est_mean_ms': estMeanMs,
      'est_sd_ms': estSdMs,
      'tasks_since_update': tasksSinceUpdate,
    };
    if (includeId) {
      map['id'] = id;
    }
    return map;
  }
}
