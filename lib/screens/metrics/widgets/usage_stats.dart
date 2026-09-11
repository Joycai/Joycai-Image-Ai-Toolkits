import '../../../models/llm_model.dart';

/// What one fee group's money went on over a range, and how many requests
/// spent it.
///
/// The usage-by-group bar is as long as the group's share of the range's
/// total, and this is what divides that length: the input, cache and output
/// parts in the token identity colours, and whatever request-billed jobs cost
/// as the neutral remainder.
class GroupUsage {
  final double inputCost;
  final double cacheCost;
  final double outputCost;

  /// Cost of request-billed rows, which bill no tokens at all.
  final double requestCost;

  final int requestCount;

  const GroupUsage({
    this.inputCost = 0,
    this.cacheCost = 0,
    this.outputCost = 0,
    this.requestCost = 0,
    this.requestCount = 0,
  });

  double get totalCost => inputCost + cacheCost + outputCost + requestCost;

  GroupUsage operator +(GroupUsage other) => GroupUsage(
        inputCost: inputCost + other.inputCost,
        cacheCost: cacheCost + other.cacheCost,
        outputCost: outputCost + other.outputCost,
        requestCost: requestCost + other.requestCost,
        requestCount: requestCount + other.requestCount,
      );
}

/// Aggregated token-usage totals for a date range, plus per-fee-group costs.
class UsageStats {
  /// Input tokens billed at the full input rate (cache misses only).
  final int totalInput;

  /// Input tokens served from the provider's prompt cache. Disjoint from
  /// [totalInput]; the two sum to the full input token count.
  final int totalCache;

  final int totalOutput;
  final int totalRequestCount;
  final double totalCost;
  final Map<int, double> groupCosts;

  /// Per-group breakdown of [groupCosts]. Empty when the stats were built
  /// without one (a checkpoint, a test); the views then draw a group's bar in
  /// one neutral colour instead of three segments.
  final Map<int, GroupUsage> groupUsage;

  UsageStats({
    required this.totalInput,
    required this.totalCache,
    required this.totalOutput,
    required this.totalRequestCount,
    required this.totalCost,
    required this.groupCosts,
    this.groupUsage = const {},
  });

  factory UsageStats.empty() => UsageStats(
        totalInput: 0,
        totalCache: 0,
        totalOutput: 0,
        totalRequestCount: 0,
        totalCost: 0.0,
        groupCosts: {},
      );

  /// Share of prompt tokens that were served from the provider's cache, 0–1.
  ///
  /// [totalInput] and [totalCache] are disjoint, so their sum is every prompt
  /// token sent in the range and the cached part divided by it is the hit rate.
  ///
  /// Null when the range holds no prompt tokens at all — a range of only
  /// request-billed image jobs never asked the cache for anything, and "0%"
  /// would report that as a cache that always misses.
  double? get cacheHitRate {
    final promptTokens = totalInput + totalCache;
    if (promptTokens == 0) return null;
    return totalCache / promptTokens;
  }
}

/// A row's cost split by what it billed, from the prices snapshotted onto it
/// at record time. Token rows bill input, cache hits and output separately;
/// request rows bill a count of requests.
///
/// `cache_price` is null on rows written before cache pricing existed, and on
/// rows whose fee group leaves the cache rate unset — both fall back to the
/// plain input rate.
({double input, double cache, double output, double request}) usageRowCostParts(
  Map<String, dynamic> row,
) {
  final billingMode = row['billing_mode'] as String? ?? 'token';

  if (billingMode != 'token') {
    final reqPrice = (row['request_price'] as num? ?? 0.0).toDouble();
    return (
      input: 0.0,
      cache: 0.0,
      output: 0.0,
      request: (row['request_count'] as int? ?? 1) * reqPrice,
    );
  }

  final inPrice = (row['input_price'] as num? ?? 0.0).toDouble();
  final outPrice = (row['output_price'] as num? ?? 0.0).toDouble();
  final cachePrice = (row['cache_price'] as num?)?.toDouble() ?? inPrice;

  return (
    input: (row['input_tokens'] as int? ?? 0) * inPrice / 1000000,
    cache: (row['cache_tokens'] as int? ?? 0) * cachePrice / 1000000,
    output: (row['output_tokens'] as int? ?? 0) * outPrice / 1000000,
    request: 0.0,
  );
}

/// Cost of a single usage row — the sum of [usageRowCostParts].
double calculateRowCost(Map<String, dynamic> row) {
  final parts = usageRowCostParts(row);
  if ((row['billing_mode'] as String? ?? 'token') != 'token') return parts.request;
  return parts.input + parts.cache + parts.output;
}

/// Computes totals and per-group costs from raw usage rows. Pure function so it
/// can be reused by both the mobile and desktop usage views. Pass [base] to
/// accumulate on top of an existing checkpoint.
UsageStats calculateStats(List<Map<String, dynamic>> usageData, List<LLMModel> allModels, {UsageStats? base}) {
  final Map<int, double> groupCosts = base != null ? Map.from(base.groupCosts) : {};
  final Map<int, GroupUsage> groupUsage = base != null ? Map.from(base.groupUsage) : {};
  int totalInput = base?.totalInput ?? 0;
  int totalCache = base?.totalCache ?? 0;
  int totalOutput = base?.totalOutput ?? 0;
  int totalRequestCount = base?.totalRequestCount ?? 0;
  double totalCost = base?.totalCost ?? 0.0;

  final modelToGroup = {for (var m in allModels) m.id: m.feeGroupId};

  for (var row in usageData) {
    final cost = calculateRowCost(row);
    final requests = row['request_count'] as int? ?? 1;

    totalInput += row['input_tokens'] as int? ?? 0;
    totalCache += row['cache_tokens'] as int? ?? 0;
    totalOutput += row['output_tokens'] as int? ?? 0;
    totalRequestCount += requests;
    totalCost += cost;

    final modelDbId = row['model_pk'] as int?;
    final groupId = modelDbId != null ? modelToGroup[modelDbId] : null;

    if (groupId != null) {
      groupCosts[groupId] = (groupCosts[groupId] ?? 0) + cost;

      final parts = usageRowCostParts(row);
      groupUsage[groupId] = (groupUsage[groupId] ?? const GroupUsage()) +
          GroupUsage(
            inputCost: parts.input,
            cacheCost: parts.cache,
            outputCost: parts.output,
            requestCost: parts.request,
            requestCount: requests,
          );
    }
  }
  return UsageStats(
    totalInput: totalInput,
    totalCache: totalCache,
    totalOutput: totalOutput,
    totalRequestCount: totalRequestCount,
    totalCost: totalCost,
    groupCosts: groupCosts,
    groupUsage: groupUsage,
  );
}
