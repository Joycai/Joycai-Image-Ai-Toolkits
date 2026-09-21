import 'dart:convert';

import 'spec_rate.dart';

/// How a usage row was billed — what its cost is a product of.
enum UsageBilling {
  /// Input, cache-hit and output tokens, each at its own per-million rate.
  token,

  /// A count of requests at a flat price each.
  request,

  /// Output units (pictures, seconds, clips) at the price of the rate-table
  /// row the request's spec landed on.
  spec;

  /// `token` and `spec` are spelled out; every other value — `request`, and
  /// anything a hand-edited fee group might hold — bills by request, which is
  /// how the usage page has always read an unknown mode.
  static UsageBilling parse(String? raw) => switch (raw ?? 'token') {
        'token' => UsageBilling.token,
        'spec' => UsageBilling.spec,
        _ => UsageBilling.request,
      };
}

/// The `token_usage.output_spec` column, decoded: the output spec one
/// spec-billed request was priced at, and whether the group's rate table had
/// a row for it.
class UsageSpecSnapshot {
  final String? size;
  final String? quality;
  final int? seconds;

  /// False when no rate row priced the spec — the request then cost zero,
  /// which is a configuration gap the usage page counts. A snapshot written
  /// without the flag cannot say, so reads as matched.
  final bool matched;

  const UsageSpecSnapshot({
    this.size,
    this.quality,
    this.seconds,
    this.matched = true,
  });

  /// Null for a missing, blank or malformed column.
  static UsageSpecSnapshot? tryDecode(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final size = decoded['size'];
      final quality = decoded['quality'];
      final seconds = decoded['seconds'];
      return UsageSpecSnapshot(
        size: size is String ? size : null,
        quality: quality is String ? quality : null,
        // toInt() throws on infinity, and one bad cell must not fail the page.
        seconds: seconds is num && seconds.isFinite ? seconds.toInt() : null,
        matched: decoded['matched'] != false,
      );
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode({
        if (size != null) 'size': size,
        if (quality != null) 'quality': quality,
        if (seconds != null) 'seconds': seconds,
        'matched': matched,
      });

  /// As the usage table's 「规格」 column spells it: `1080p · high · 8s`, the
  /// absent dimensions left out — empty for a request that carried no spec.
  String get label => [
        ?size,
        ?quality,
        if (seconds != null) '${seconds}s',
      ].join(' · ');
}

/// The four columns a spec-billed request leaves on its usage row
/// (`output_units`, `output_unit_price`, `output_unit`, `output_spec`).
///
/// Its own type because they are also written on their own: a finished video
/// job re-prices the row its submit recorded by the seconds that were
/// actually rendered (`UsageRepository.updateSpecBilling`).
class UsageSpecBilling {
  /// Null on a row whose `output_unit` is missing or names no [OutputUnit].
  final OutputUnit? unit;
  final double units;
  final double unitPrice;
  final UsageSpecSnapshot? snapshot;

  const UsageSpecBilling({
    this.unit,
    required this.units,
    required this.unitPrice,
    this.snapshot,
  });

  double get cost => units * unitPrice;

  Map<String, dynamic> toMap() => {
        'output_units': units,
        'output_unit_price': unitPrice,
        'output_unit': unit?.name,
        'output_spec': snapshot?.encode(),
      };

  /// Null when [map] says nothing in any of the four columns — every row of
  /// the other two billing modes. "Nothing" is NULL *or zero* for the two
  /// numbers: a row that predates v42 was given `DEFAULT 0.0` by the ALTER,
  /// while one written since carries NULL, and both mean the same.
  static UsageSpecBilling? fromMap(Map<String, dynamic> map) {
    final units = map['output_units'] as num?;
    final unitPrice = map['output_unit_price'] as num?;
    final rawUnit = map['output_unit'] as String?;
    final snapshot = UsageSpecSnapshot.tryDecode(map['output_spec']);
    if ((units ?? 0) == 0 && (unitPrice ?? 0) == 0 && rawUnit == null && snapshot == null) {
      return null;
    }
    return UsageSpecBilling(
      unit: OutputUnit.values.where((u) => u.name == rawUnit).firstOrNull,
      units: (units ?? 0.0).toDouble(),
      unitPrice: (unitPrice ?? 0.0).toDouble(),
      snapshot: snapshot,
    );
  }
}

/// A usage row's cost, split by what it billed. Only one billing mode's parts
/// are ever non-zero.
typedef UsageCostParts = ({
  double input,
  double cache,
  double output,
  double request,
  double spec,
});

/// One row of `token_usage`: what a single billed request used, with the
/// prices of its fee group snapshotted at record time — so re-pricing a group
/// later never rewrites history.
class TokenUsage {
  final int? id;

  /// Not the queue's task id: a tag plus a timestamp (`req_…`,
  /// `subagent:…`), or a video job's row id so its settle can find it.
  final String? taskId;

  /// The model's display id as it was when the request ran.
  final String modelId;

  /// The model's row in `llm_models`; null for a row recorded before v9 or
  /// against a model addressed by string.
  final int? modelDbId;

  final DateTime timestamp;

  /// Prompt tokens billed at the full input rate. Disjoint from
  /// [cacheTokens]; the two sum to the whole prompt.
  final int inputTokens;
  final int cacheTokens;
  final int outputTokens;

  /// Per million tokens.
  final double inputPrice;
  final double outputPrice;

  /// Null on rows written before cache pricing existed, and on rows whose fee
  /// group leaves the cache rate unset — read [effectiveCachePrice].
  final double? cachePrice;

  final int requestCount;
  final double requestPrice;

  /// The fee group's `billing_mode` as stored. Read [billing].
  final String billingMode;

  /// What a spec-billed request counted and at what price; null on the other
  /// two modes. Whether the row *is* spec-billed is [billing]'s to say — a
  /// spec row whose columns were lost reads null here too, and prices zero.
  final UsageSpecBilling? spec;

  const TokenUsage({
    this.id,
    this.taskId,
    required this.modelId,
    this.modelDbId,
    required this.timestamp,
    this.inputTokens = 0,
    this.cacheTokens = 0,
    this.outputTokens = 0,
    this.inputPrice = 0.0,
    this.outputPrice = 0.0,
    this.cachePrice,
    this.requestCount = 1,
    this.requestPrice = 0.0,
    this.billingMode = 'token',
    this.spec,
  });

  UsageBilling get billing => UsageBilling.parse(billingMode);

  double get effectiveCachePrice => cachePrice ?? inputPrice;

  /// The cost split by what was billed, from the prices on the row itself.
  UsageCostParts get costParts => switch (billing) {
        UsageBilling.spec =>
          (input: 0.0, cache: 0.0, output: 0.0, request: 0.0, spec: spec?.cost ?? 0.0),
        UsageBilling.request => (
            input: 0.0,
            cache: 0.0,
            output: 0.0,
            request: requestCount * requestPrice,
            spec: 0.0,
          ),
        UsageBilling.token => (
            input: inputTokens * inputPrice / 1000000,
            cache: cacheTokens * effectiveCachePrice / 1000000,
            output: outputTokens * outputPrice / 1000000,
            request: 0.0,
            spec: 0.0,
          ),
      };

  double get cost {
    final parts = costParts;
    return parts.input + parts.cache + parts.output + parts.request + parts.spec;
  }

  /// Whether this spec-billed request found no rate row for its spec. Rows of
  /// the other modes are never unmatched.
  bool get unmatched =>
      billing == UsageBilling.spec && spec?.snapshot?.matched == false;

  /// The spec this row was billed at; null for a row of another mode or one
  /// without the snapshot, empty for a request that carried no spec at all.
  String? get specLabel =>
      billing == UsageBilling.spec ? spec?.snapshot?.label : null;

  factory TokenUsage.fromMap(Map<String, dynamic> map) => TokenUsage(
        id: map['id'] as int?,
        taskId: map['task_id'] as String?,
        modelId: map['model_id'] as String? ?? '',
        modelDbId: map['model_pk'] as int?,
        timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        inputTokens: map['input_tokens'] as int? ?? 0,
        cacheTokens: map['cache_tokens'] as int? ?? 0,
        outputTokens: map['output_tokens'] as int? ?? 0,
        inputPrice: (map['input_price'] as num? ?? 0.0).toDouble(),
        outputPrice: (map['output_price'] as num? ?? 0.0).toDouble(),
        cachePrice: (map['cache_price'] as num?)?.toDouble(),
        requestCount: map['request_count'] as int? ?? 1,
        requestPrice: (map['request_price'] as num? ?? 0.0).toDouble(),
        billingMode: map['billing_mode'] as String? ?? 'token',
        spec: UsageSpecBilling.fromMap(map),
      );

  /// The row as inserted. A row without [spec] writes its four columns as
  /// NULL, so it prices exactly as it did before spec billing existed.
  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'task_id': taskId,
        'model_id': modelId,
        'model_pk': modelDbId,
        'timestamp': timestamp.toIso8601String(),
        'input_tokens': inputTokens,
        'cache_tokens': cacheTokens,
        'output_tokens': outputTokens,
        'input_price': inputPrice,
        'cache_price': cachePrice,
        'output_price': outputPrice,
        'request_count': requestCount,
        'request_price': requestPrice,
        'billing_mode': billingMode,
        ...spec?.toMap() ??
            const {
              'output_units': null,
              'output_unit_price': null,
              'output_unit': null,
              'output_spec': null,
            },
      };
}
