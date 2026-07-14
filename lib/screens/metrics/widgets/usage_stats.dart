import '../../../models/llm_model.dart';

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

  UsageStats({
    required this.totalInput,
    required this.totalCache,
    required this.totalOutput,
    required this.totalRequestCount,
    required this.totalCost,
    required this.groupCosts,
  });

  factory UsageStats.empty() => UsageStats(
        totalInput: 0,
        totalCache: 0,
        totalOutput: 0,
        totalRequestCount: 0,
        totalCost: 0.0,
        groupCosts: {},
      );
}

/// Cost of a single usage row, from the prices snapshotted onto it at record
/// time. Token rows bill input, cache hits and output separately.
///
/// `cache_price` is null on rows written before cache pricing existed, and on
/// rows whose fee group leaves the cache rate unset — both fall back to the
/// plain input rate.
double calculateRowCost(Map<String, dynamic> row) {
  final billingMode = row['billing_mode'] as String? ?? 'token';

  if (billingMode != 'token') {
    final reqPrice = (row['request_price'] as num? ?? 0.0).toDouble();
    return (row['request_count'] as int? ?? 1) * reqPrice;
  }

  final inPrice = (row['input_price'] as num? ?? 0.0).toDouble();
  final outPrice = (row['output_price'] as num? ?? 0.0).toDouble();
  final cachePrice = (row['cache_price'] as num?)?.toDouble() ?? inPrice;

  return ((row['input_tokens'] as int? ?? 0) * inPrice / 1000000) +
      ((row['cache_tokens'] as int? ?? 0) * cachePrice / 1000000) +
      ((row['output_tokens'] as int? ?? 0) * outPrice / 1000000);
}

/// Computes totals and per-group costs from raw usage rows. Pure function so it
/// can be reused by both the mobile and desktop usage views. Pass [base] to
/// accumulate on top of an existing checkpoint.
UsageStats calculateStats(List<Map<String, dynamic>> usageData, List<LLMModel> allModels, {UsageStats? base}) {
  final Map<int, double> groupCosts = base != null ? Map.from(base.groupCosts) : {};
  int totalInput = base?.totalInput ?? 0;
  int totalCache = base?.totalCache ?? 0;
  int totalOutput = base?.totalOutput ?? 0;
  int totalRequestCount = base?.totalRequestCount ?? 0;
  double totalCost = base?.totalCost ?? 0.0;

  final modelToGroup = {for (var m in allModels) m.id: m.feeGroupId};

  for (var row in usageData) {
    final cost = calculateRowCost(row);

    totalInput += row['input_tokens'] as int? ?? 0;
    totalCache += row['cache_tokens'] as int? ?? 0;
    totalOutput += row['output_tokens'] as int? ?? 0;
    totalRequestCount += row['request_count'] as int? ?? 1;
    totalCost += cost;

    final modelDbId = row['model_pk'] as int?;
    final groupId = modelDbId != null ? modelToGroup[modelDbId] : null;

    if (groupId != null) {
      groupCosts[groupId] = (groupCosts[groupId] ?? 0) + cost;
    }
  }
  return UsageStats(
    totalInput: totalInput,
    totalCache: totalCache,
    totalOutput: totalOutput,
    totalRequestCount: totalRequestCount,
    totalCost: totalCost,
    groupCosts: groupCosts,
  );
}
