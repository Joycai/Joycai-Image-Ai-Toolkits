import 'dart:convert';

import 'spec_rate.dart';

// A cell of the wrong type reads as absent. SQLite keeps text in a REAL
// column as text, and a row is decoded whole whatever its billing mode — so a
// cast here would let one hand-edited cell fail the page it is on, including
// a cell that row's own mode never reads.
int? _int(Object? cell) => cell is int ? cell : null;
double? _double(Object? cell) => cell is num ? cell.toDouble() : null;
String? _text(Object? cell) => cell is String ? cell : null;

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

/// The columns a spec-billed request leaves on its usage row: the output
/// four (`output_units`, `output_unit_price`, `output_unit`, `output_spec`)
/// and the input three (`input_images`, `input_units`, `input_unit_price`, v48).
///
/// Its own type because the output four are also written on their own: a
/// finished video job re-prices the row its submit recorded by the seconds
/// that were actually rendered (`UsageRepository.updateSpecBilling`) — see
/// [toOutputMap] for why that write leaves the input three alone.
class UsageSpecBilling {
  /// Null on a row without the column. A value that names no [OutputUnit]
  /// reads as [OutputUnit.image] — what the usage page has always drawn for
  /// one, and what [OutputUnit.parse] gives a fee group.
  final OutputUnit? unit;
  final double units;
  final double unitPrice;
  final UsageSpecSnapshot? snapshot;

  /// Reference images the request actually sent, before the fee group's free
  /// ones came off — what the usage page shows. Its own column rather than a
  /// key of the snapshot, which a video settle rewrites whole. Zero on every
  /// row written before v48.
  final int inputImages;

  /// Reference images *billed* — [inputImages] less the free ones — and the
  /// price of each. Both zero on a group that does not charge for inputs.
  final double inputUnits;
  final double inputUnitPrice;

  const UsageSpecBilling({
    this.unit,
    required this.units,
    required this.unitPrice,
    this.snapshot,
    this.inputImages = 0,
    this.inputUnits = 0.0,
    this.inputUnitPrice = 0.0,
  });

  /// What the output cost. The input side is [inputCost]; a row's total is
  /// the two together ([TokenUsage.cost]).
  double get cost => units * unitPrice;

  double get inputCost => inputUnits * inputUnitPrice;

  /// The row as inserted: all seven columns.
  Map<String, dynamic> toMap() => {
        ...toOutputMap(),
        'input_images': inputImages,
        'input_units': inputUnits,
        'input_unit_price': inputUnitPrice,
      };

  /// The output four alone — what re-pricing a row writes. A video settle
  /// knows the seconds that were rendered and nothing about the images the
  /// submit sent, so writing the input three from it would zero what the
  /// submit recorded.
  Map<String, dynamic> toOutputMap() => {
        'output_units': units,
        'output_unit_price': unitPrice,
        'output_unit': unit?.name,
        'output_spec': snapshot?.encode(),
      };

  /// Null when [map] says nothing in any of the seven columns — every row of
  /// the other two billing modes. "Nothing" is NULL *or zero* for the five
  /// numbers: a row that predates v42 was given `DEFAULT 0.0` by the ALTER,
  /// while one written since carries NULL, and both mean the same.
  static UsageSpecBilling? fromMap(Map<String, dynamic> map) {
    final units = _double(map['output_units']) ?? 0.0;
    final unitPrice = _double(map['output_unit_price']) ?? 0.0;
    final rawUnit = _text(map['output_unit']);
    final snapshot = UsageSpecSnapshot.tryDecode(map['output_spec']);
    final inputImages = _int(map['input_images']) ?? 0;
    final inputUnits = _double(map['input_units']) ?? 0.0;
    final inputUnitPrice = _double(map['input_unit_price']) ?? 0.0;
    if (units == 0 &&
        unitPrice == 0 &&
        rawUnit == null &&
        snapshot == null &&
        inputImages == 0 &&
        inputUnits == 0 &&
        inputUnitPrice == 0) {
      return null;
    }
    return UsageSpecBilling(
      unit: rawUnit == null ? null : OutputUnit.parse(rawUnit),
      units: units,
      unitPrice: unitPrice,
      snapshot: snapshot,
      inputImages: inputImages,
      inputUnits: inputUnits,
      inputUnitPrice: inputUnitPrice,
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

  /// Reference images a spec-billed request was charged for — beside
  /// [spec], which is its output alone.
  double specInput,

  /// What the provider itself said the request cost ([TokenUsage.reportedCost]).
  /// When it is set every other part is zero: the figure is the whole charge,
  /// and it replaces the snapshot rather than adding to it.
  double reported,
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

  /// Null only on rows written before cache pricing existed (v30): the
  /// recorder snapshots the *resolved* rate, so a fee group that leaves the
  /// cache rate unset still writes its input rate here. Read
  /// [effectiveCachePrice], which falls back the same way.
  final double? cachePrice;

  final int requestCount;
  final double requestPrice;

  /// The fee group's `billing_mode` as stored. Read [billing].
  final String billingMode;

  /// What a spec-billed request counted and at what price; null on every row
  /// the app writes in the other two modes. Whether the row *is* spec-billed
  /// is [billing]'s to say, not this field's: a spec row whose columns were
  /// lost reads null here too (and prices zero), and a hand-edited token row
  /// may carry one that nothing bills.
  final UsageSpecBilling? spec;

  /// The money the provider itself reported for this request, in dollars —
  /// xAI's `cost_in_usd_ticks`, reference images included — or null where
  /// the provider reported none (every row before v49, every other vendor).
  /// It outranks the row's own prices under every mode ([costParts]): the
  /// snapshot beside it is what the fee group *would* have charged, kept so
  /// the usage page can show the two against each other. A reported zero is
  /// a reported figure; only null means "not reported".
  final double? reportedCost;

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
    this.reportedCost,
  });

  UsageBilling get billing => UsageBilling.parse(billingMode);

  double get effectiveCachePrice => cachePrice ?? inputPrice;

  /// The cost split by what was billed, from the prices on the row itself —
  /// or, where the provider reported the charge, that figure alone.
  UsageCostParts get costParts {
    final reported = reportedCost;
    if (reported != null) {
      return (
        input: 0.0,
        cache: 0.0,
        output: 0.0,
        request: 0.0,
        spec: 0.0,
        specInput: 0.0,
        reported: reported,
      );
    }
    return switch (billing) {
      UsageBilling.spec => (
          input: 0.0,
          cache: 0.0,
          output: 0.0,
          request: 0.0,
          spec: spec?.cost ?? 0.0,
          specInput: spec?.inputCost ?? 0.0,
          reported: 0.0,
        ),
      UsageBilling.request => (
          input: 0.0,
          cache: 0.0,
          output: 0.0,
          request: requestCount * requestPrice,
          spec: 0.0,
          specInput: 0.0,
          reported: 0.0,
        ),
      UsageBilling.token => (
          input: inputTokens * inputPrice / 1000000,
          cache: cacheTokens * effectiveCachePrice / 1000000,
          output: outputTokens * outputPrice / 1000000,
          request: 0.0,
          spec: 0.0,
          specInput: 0.0,
          reported: 0.0,
        ),
    };
  }

  double get cost {
    final parts = costParts;
    return parts.input +
        parts.cache +
        parts.output +
        parts.request +
        parts.spec +
        parts.specInput +
        parts.reported;
  }

  /// What the fee group's snapshot on this row would charge, whatever the
  /// provider reported: [cost] without the override. Equal to [cost] on a
  /// row without a reported figure. The usage page sets it against
  /// [reportedCost] — a gap is the rate table disagreeing with the invoice.
  double get snapshotCost => reportedCost == null
      ? cost
      : TokenUsage(
          modelId: modelId,
          timestamp: timestamp,
          inputTokens: inputTokens,
          cacheTokens: cacheTokens,
          outputTokens: outputTokens,
          inputPrice: inputPrice,
          outputPrice: outputPrice,
          cachePrice: cachePrice,
          requestCount: requestCount,
          requestPrice: requestPrice,
          billingMode: billingMode,
          spec: spec,
        ).cost;

  /// Whether this spec-billed request found no rate row for its spec. Rows of
  /// the other modes are never unmatched — nor is a row the provider priced
  /// itself: the gap a missing rate row leaves is filled by the report, and
  /// the nudge to go and add the row would be sending the user to fix
  /// nothing.
  bool get unmatched =>
      billing == UsageBilling.spec &&
      spec?.snapshot?.matched == false &&
      reportedCost == null;

  /// The spec this row was billed at; null for a row of another mode or one
  /// without the snapshot, empty for a request that carried no spec at all.
  String? get specLabel =>
      billing == UsageBilling.spec ? spec?.snapshot?.label : null;

  factory TokenUsage.fromMap(Map<String, dynamic> map) => TokenUsage(
        id: _int(map['id']),
        taskId: _text(map['task_id']),
        modelId: _text(map['model_id']) ?? '',
        modelDbId: _int(map['model_pk']),
        timestamp: DateTime.tryParse(_text(map['timestamp']) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        inputTokens: _int(map['input_tokens']) ?? 0,
        cacheTokens: _int(map['cache_tokens']) ?? 0,
        outputTokens: _int(map['output_tokens']) ?? 0,
        inputPrice: _double(map['input_price']) ?? 0.0,
        outputPrice: _double(map['output_price']) ?? 0.0,
        cachePrice: _double(map['cache_price']),
        requestCount: _int(map['request_count']) ?? 1,
        requestPrice: _double(map['request_price']) ?? 0.0,
        billingMode: _text(map['billing_mode']) ?? 'token',
        spec: UsageSpecBilling.fromMap(map),
        // A negative or non-finite cell is nobody's report.
        reportedCost: switch (_double(map['reported_cost'])) {
          final v? when v.isFinite && v >= 0 => v,
          _ => null,
        },
      );

  /// The row as inserted. A row without [spec] writes its seven columns as
  /// NULL, so it prices exactly as it did before spec billing existed; one
  /// without a reported cost writes NULL there too.
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
              'input_images': null,
              'input_units': null,
              'input_unit_price': null,
            },
        'reported_cost': reportedCost,
      };
}
