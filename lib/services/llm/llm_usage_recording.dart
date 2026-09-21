part of 'llm_service.dart';

/// Recording what a request cost — the usage row [LLMService] writes after
/// every billed response.
extension _UsageRecording on LLMService {
  /// [options] and [imageCount] feed spec billing: the request's output
  /// spec (size / quality / seconds) is read off the options — or off the
  /// provider's echo in [metadata] where there is one — and priced against
  /// the group's rate table; the units are the pictures the response
  /// carried, the seconds requested, or one per job. See [LLMService.specUsageFor].
  ///
  /// **Best-effort: never throws** (standard 06 §1). It runs after the
  /// provider has already generated — and billed — the output, so a locked
  /// database or a bad spec table must not turn a delivered image into a
  /// failed task, or lose an accepted video job's ticket before its id is
  /// persisted. A failure is logged at WARN and swallowed.
  Future<void> _recordUsage(
    String modelId,
    LLMModelConfig config,
    Map<String, dynamic> metadata, {
    int? modelDbId,
    String? taskTag,
    Map<String, dynamic>? options,
    int imageCount = 0,
    String? rowId,
  }) async {
    try {
      await _writeUsageRow(modelId, config, metadata,
          modelDbId: modelDbId,
          taskTag: taskTag,
          options: options,
          imageCount: imageCount,
          rowId: rowId);
    } catch (e) {
      _emitLog(
        'Usage for $modelId could not be recorded (the response itself is '
        'unaffected): $e',
        level: 'WARN',
      );
    }
  }

  Future<void> _writeUsageRow(
    String modelId,
    LLMModelConfig config,
    Map<String, dynamic> metadata, {
    int? modelDbId,
    String? taskTag,
    Map<String, dynamic>? options,
    int imageCount = 0,
    String? rowId,
  }) async {
    final spec = LLMService.specUsageFor(config, options, metadata, imageCount: imageCount);

    // Standardize metadata keys. Three spellings are in play: Google
    // (`promptTokenCount`), OpenAI chat (`prompt_tokens`) and the OpenAI
    // *Images* API (`input_tokens`) — gpt-image-1 reports only the third, so
    // reading the first two alone recorded every image generation as zero
    // tokens and only request-billed channels came out right.
    final promptTokens = _asTokenCount(
      metadata['promptTokenCount'] ??
          metadata['prompt_tokens'] ??
          metadata['input_tokens'],
    );
    final outputTokens = LLMService.outputTokensOf(metadata);
    final cacheTokens = _extractCacheTokens(metadata, promptTokens);

    final sink = LLMService.usageSinkOverride ?? DatabaseService().recordTokenUsage;
    await sink(TokenUsage(
      // The tag makes delegated work distinguishable in the usage table
      // (e.g. `task_id LIKE 'subagent:%'`) — a sub-agent's spend should be
      // attributable to delegation, not blended into ordinary requests.
      taskId: rowId ??
          '${taskTag ?? 'req'}_${DateTime.now().millisecondsSinceEpoch}',
      modelId: modelId,
      modelDbId: modelDbId,
      timestamp: DateTime.now(),
      // Both providers count cached tokens inside their prompt total, so the
      // cached part is subtracted out here — input_tokens and cache_tokens are
      // stored disjoint and sum back to the full input.
      inputTokens: promptTokens - cacheTokens,
      cacheTokens: cacheTokens,
      outputTokens: outputTokens,
      inputPrice: config.inputFee,
      cachePrice: config.effectiveCacheInputFee,
      outputPrice: config.outputFee,
      requestPrice: config.requestFee,
      billingMode: config.billingMode,
      // Null on the other two modes: the row then prices exactly as it did
      // before spec billing existed.
      spec: spec?.toBilling(),
    ));
  }

  /// Cache-hit tokens from a usage payload: `cachedContentTokenCount` (Google),
  /// `prompt_tokens_details.cached_tokens` (OpenAI) or `cache_read_input_tokens`
  /// (Anthropic). Clamped to [promptTokens] so a malformed payload can never
  /// drive the uncached remainder negative.
  ///
  /// Anthropic's bucket is only comparable to the other two because its
  /// protocol already republished the *inclusive* prompt total as
  /// `prompt_tokens` — its own `input_tokens` excludes the cached part, so
  /// subtracting one from the other would count the cache twice.
  int _extractCacheTokens(Map<String, dynamic> metadata, int promptTokens) {
    final details = metadata['prompt_tokens_details'];
    final raw =
        metadata['cachedContentTokenCount'] ??
        metadata['cache_read_input_tokens'] ??
        (details is Map ? details['cached_tokens'] : null);
    return _asTokenCount(raw).clamp(0, promptTokens);
  }

  /// Token counts arrive as int, double or String depending on provider and
  /// transport; anything unparseable counts as zero.
  int _asTokenCount(dynamic value) {
    final count = value is num
        ? value.toInt()
        : (value is String ? int.tryParse(value) : null);
    return (count == null || count < 0) ? 0 : count;
  }
}

String _missingUsageWarning(LLMModelConfig config) =>
    'The provider reported no token usage for ${config.modelId} on a '
    'token-billed channel; this request is recorded as 0 tokens although '
    'it was probably billed.';

int _asTokenCountStatic(dynamic value) {
  final count = value is num
      ? value.toInt()
      : (value is String ? int.tryParse(value) : null);
  return (count == null || count < 0) ? 0 : count;
}
