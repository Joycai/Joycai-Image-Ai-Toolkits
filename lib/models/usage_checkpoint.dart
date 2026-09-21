import 'dart:convert';

/// One row of `usage_checkpoints`: a range's totals as they stood at
/// [timestamp], written at most daily by a usage view over a large range.
class UsageCheckpoint {
  final int? id;
  final DateTime timestamp;
  final int totalInputTokens;
  final int totalCacheTokens;
  final int totalOutputTokens;
  final int totalRequestCount;
  final double totalCost;

  /// Cost by fee-group id — the `metadata` column.
  final Map<int, double> groupCosts;

  const UsageCheckpoint({
    this.id,
    required this.timestamp,
    this.totalInputTokens = 0,
    this.totalCacheTokens = 0,
    this.totalOutputTokens = 0,
    this.totalRequestCount = 0,
    this.totalCost = 0.0,
    this.groupCosts = const {},
  });

  factory UsageCheckpoint.fromMap(Map<String, dynamic> map) => UsageCheckpoint(
        id: map['id'] as int?,
        timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        totalInputTokens: map['total_input_tokens'] as int? ?? 0,
        totalCacheTokens: map['total_cache_tokens'] as int? ?? 0,
        totalOutputTokens: map['total_output_tokens'] as int? ?? 0,
        totalRequestCount: map['total_request_count'] as int? ?? 0,
        totalCost: (map['total_cost'] as num? ?? 0.0).toDouble(),
        groupCosts: _decodeGroupCosts(map['metadata']),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'timestamp': timestamp.toIso8601String(),
        'total_input_tokens': totalInputTokens,
        'total_cache_tokens': totalCacheTokens,
        'total_output_tokens': totalOutputTokens,
        'total_request_count': totalRequestCount,
        'total_cost': totalCost,
        // Keyed by int group id; jsonEncode throws JsonUnsupportedObjectError
        // on any non-String map key, so the keys are stringified first.
        'metadata': jsonEncode(groupCosts.map((k, v) => MapEntry(k.toString(), v))),
      };

  static Map<int, double> _decodeGroupCosts(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final costs = <int, double>{};
      for (final e in decoded.entries) {
        final id = int.tryParse(e.key.toString());
        final value = e.value;
        if (id != null && value is num) costs[id] = value.toDouble();
      }
      return costs;
    } on FormatException {
      return const {};
    }
  }
}
