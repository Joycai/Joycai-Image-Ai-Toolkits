import '../../../models/llm_model.dart';
import '../../../models/spec_rate.dart';
import '../../../models/token_usage.dart';

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

  /// Cost of spec-billed rows (images by size, video by resolution and
  /// length). Drawn in the same neutral as [requestCost] — both are money
  /// that bought output rather than tokens — and told apart in text.
  final double specCost;

  /// Units the spec-billed rows used, by unit, for the "38 images · 126 s"
  /// line.
  final Map<OutputUnit, double> specUnits;

  /// Spec-billed requests whose rate table had no row for their spec. They
  /// cost zero, which is a configuration gap, not a free lunch.
  final int unmatchedCount;

  final int requestCount;

  const GroupUsage({
    this.inputCost = 0,
    this.cacheCost = 0,
    this.outputCost = 0,
    this.requestCost = 0,
    this.specCost = 0,
    this.specUnits = const {},
    this.unmatchedCount = 0,
    this.requestCount = 0,
  });

  double get totalCost => inputCost + cacheCost + outputCost + requestCost + specCost;

  GroupUsage operator +(GroupUsage other) => GroupUsage(
        inputCost: inputCost + other.inputCost,
        cacheCost: cacheCost + other.cacheCost,
        outputCost: outputCost + other.outputCost,
        requestCost: requestCost + other.requestCost,
        specCost: specCost + other.specCost,
        specUnits: {
          ...specUnits,
          for (final e in other.specUnits.entries)
            e.key: (specUnits[e.key] ?? 0) + e.value,
        },
        unmatchedCount: unmatchedCount + other.unmatchedCount,
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

/// Computes totals and per-group costs from usage records. Pure function so it
/// can be reused by both the mobile and desktop usage views. Pass [base] to
/// accumulate on top of an existing checkpoint.
UsageStats calculateStats(List<TokenUsage> usageData, List<LLMModel> allModels, {UsageStats? base}) {
  final Map<int, double> groupCosts = base != null ? Map.from(base.groupCosts) : {};
  final Map<int, GroupUsage> groupUsage = base != null ? Map.from(base.groupUsage) : {};
  int totalInput = base?.totalInput ?? 0;
  int totalCache = base?.totalCache ?? 0;
  int totalOutput = base?.totalOutput ?? 0;
  int totalRequestCount = base?.totalRequestCount ?? 0;
  double totalCost = base?.totalCost ?? 0.0;

  final modelToGroup = {for (var m in allModels) m.id: m.feeGroupId};

  for (var row in usageData) {
    final cost = row.cost;
    final requests = row.requestCount;

    totalInput += row.inputTokens;
    totalCache += row.cacheTokens;
    totalOutput += row.outputTokens;
    totalRequestCount += requests;
    totalCost += cost;

    final modelDbId = row.modelDbId;
    final groupId = modelDbId != null ? modelToGroup[modelDbId] : null;

    if (groupId != null) {
      groupCosts[groupId] = (groupCosts[groupId] ?? 0) + cost;

      final parts = row.costParts;
      final spec = row.spec;
      final specUnit = spec?.unit;
      groupUsage[groupId] = (groupUsage[groupId] ?? const GroupUsage()) +
          GroupUsage(
            inputCost: parts.input,
            cacheCost: parts.cache,
            outputCost: parts.output,
            requestCost: parts.request,
            specCost: parts.spec,
            specUnits: spec == null || specUnit == null ? const {} : {specUnit: spec.units},
            unmatchedCount: row.unmatched ? 1 : 0,
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
