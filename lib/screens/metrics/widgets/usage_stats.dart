import '../../../models/llm_model.dart';

/// Aggregated token-usage totals for a date range, plus per-fee-group costs.
class UsageStats {
  final int totalInput;
  final int totalOutput;
  final int totalRequestCount;
  final double totalCost;
  final Map<int, double> groupCosts;

  UsageStats({
    required this.totalInput,
    required this.totalOutput,
    required this.totalRequestCount,
    required this.totalCost,
    required this.groupCosts,
  });

  factory UsageStats.empty() => UsageStats(totalInput: 0, totalOutput: 0, totalRequestCount: 0, totalCost: 0.0, groupCosts: {});
}

/// Computes totals and per-group costs from raw usage rows. Pure function so it
/// can be reused by both the mobile and desktop usage views. Pass [base] to
/// accumulate on top of an existing checkpoint.
UsageStats calculateStats(List<Map<String, dynamic>> usageData, List<LLMModel> allModels, {UsageStats? base}) {
  final Map<int, double> groupCosts = base != null ? Map.from(base.groupCosts) : {};
  int totalInput = base?.totalInput ?? 0;
  int totalOutput = base?.totalOutput ?? 0;
  int totalRequestCount = base?.totalRequestCount ?? 0;
  double totalCost = base?.totalCost ?? 0.0;

  final modelToGroup = {for (var m in allModels) m.id: m.feeGroupId};

  for (var row in usageData) {
    final input = row['input_tokens'] as int? ?? 0;
    final output = row['output_tokens'] as int? ?? 0;
    final billingMode = row['billing_mode'] as String? ?? 'token';
    final reqCount = row['request_count'] as int? ?? 1;

    double cost = 0.0;
    if (billingMode == 'token') {
      final inPrice = (row['input_price'] ?? 0.0) as num;
      final outPrice = (row['output_price'] ?? 0.0) as num;
      cost = (input * inPrice.toDouble() / 1000000) +
             (output * outPrice.toDouble() / 1000000);
    } else {
      final reqPrice = (row['request_price'] ?? 0.0) as num;
      cost = reqCount * reqPrice.toDouble();
    }

    totalInput += input;
    totalOutput += output;
    totalRequestCount += reqCount;
    totalCost += cost;

    final modelDbId = row['model_pk'] as int?;
    final groupId = modelDbId != null ? modelToGroup[modelDbId] : null;

    if (groupId != null) {
      groupCosts[groupId] = (groupCosts[groupId] ?? 0) + cost;
    }
  }
  return UsageStats(
    totalInput: totalInput,
    totalOutput: totalOutput,
    totalRequestCount: totalRequestCount,
    totalCost: totalCost,
    groupCosts: groupCosts,
  );
}
