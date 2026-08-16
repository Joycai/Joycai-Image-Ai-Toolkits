class LLMModel {
  final int? id;
  final String modelId;
  final String modelName;
  final String tag; // image, chat, multimodal
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
    this.forceViewAllImages = false,
    this.enableThinking = false,
    this.reasoningEffort,
    this.enableWebSearch = false,
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
      forceViewAllImages: (map['force_view_all_images'] ?? 0) == 1,
      enableThinking: (map['enable_thinking'] ?? 0) == 1,
      reasoningEffort: map['reasoning_effort'] as String?,
      enableWebSearch: (map['enable_web_search'] ?? 0) == 1,
      estMeanMs: map['est_mean_ms'] as double?,
      estSdMs: map['est_sd_ms'] as double?,
      tasksSinceUpdate: map['tasks_since_update'] as int? ?? 0,
    );
  }

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
      'force_view_all_images': forceViewAllImages ? 1 : 0,
      'enable_thinking': enableThinking ? 1 : 0,
      'reasoning_effort': reasoningEffort,
      'enable_web_search': enableWebSearch ? 1 : 0,
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
