/// A pixel size spelled `WxH`, parsed — or null when [raw] is not one.
///
/// The one reader of that spelling, because four were in play and each
/// surface understood a different subset: the app writes `1024x1024`,
/// DashScope's dialect is `1024*1024`, hand-typed rate tables and relays use
/// `X` or `×`. The OpenAI Images size and the video size only matched a
/// lowercase `x`, so a `1024*1024` carried over from a DashScope selection was
/// silently dropped and the upstream default — often a pricier tier — was
/// rendered instead. Surrounding and inner whitespace is tolerated.
({int width, int height})? parseWxH(Object? raw) {
  if (raw is! String) return null;
  final m = RegExp(r'^\s*(\d+)\s*[xX*×]\s*(\d+)\s*$').firstMatch(raw);
  if (m == null) return null;
  final w = int.parse(m.group(1)!);
  final h = int.parse(m.group(2)!);
  if (w <= 0 || h <= 0) return null;
  return (width: w, height: h);
}

/// The output spec of one generation request, read off the workbench
/// parameters it was sent with — the only thing a spec-billed fee group's
/// rate table can be matched against.
///
/// Read here and nowhere else: the parameter keys are the workbench's
/// (`imageSize`, `resolution`, `quality`, `videoQuality`, `seconds`), not any
/// vendor's, so this stays inside the three-layer rules. A protocol that gets
/// the *actual* spec echoed back (the OpenAI Images API reports the size and
/// quality it settled on when the request said `auto`) republishes it in the
/// response metadata as `output_size` / `output_quality` / `output_seconds`,
/// and that echo wins over what was asked for.
/// The metadata key an images protocol publishes the number of reference
/// images it actually put in the request under — after the model's cap and
/// after dropping the ones that could not be read — or the provider's own
/// count where it reports one (Ark's `usage.input_images`). Spec billing
/// charges inputs by it; a surface that does not publish it reads as zero.
const String inputImageCountKey = 'input_image_count';

/// [inputImageCountKey] off a response's metadata; absent, negative or not a
/// number reads as zero.
int inputImageCountOf(Map<String, dynamic>? metadata) {
  final raw = metadata?[inputImageCountKey];
  final count = raw is num && raw.isFinite
      ? raw.toInt()
      : (raw is String ? int.tryParse(raw) : null);
  return (count == null || count < 0) ? 0 : count;
}

/// The [inputImageCountKey] entry of [metadata] alone, or null without one —
/// what an image chunk carries ahead of the closing chunk. A stream that is
/// abandoned after a picture arrived is still billed for it
/// (`LLMService.requestStream`'s early exit), and the references that
/// picture was made from were sent all the same; the closing chunk, which
/// holds the full metadata, may never come.
Map<String, dynamic>? inputImageCountEntry(Map<String, dynamic>? metadata) {
  final count = inputImageCountOf(metadata);
  return count > 0 ? {inputImageCountKey: count} : null;
}

/// The metadata key a protocol publishes the money the provider says this
/// request cost under, in US dollars — where the provider reports one (xAI's
/// `usage.cost_in_usd_ticks`, 1 tick = $10⁻¹⁰, docs/api/usage.md §5). The
/// figure is the provider's whole charge, reference images included, so the
/// usage row bills by it instead of the fee group's table
/// ([TokenUsage.reportedCost]). The unit conversion is the protocol's: the
/// recorder reads dollars and never a vendor's own field.
///
/// Published only by a vendor's own wire. A relay forwarding the same block
/// charges its own price, which the user's rate table states — so the relay
/// protocols leave this key alone.
const String reportedCostKey = 'reported_cost_usd';

/// [reportedCostKey] off a response's metadata; absent, negative or not a
/// finite number reads as "not reported" (null), never as zero — a zero is
/// something only the provider gets to say.
double? reportedCostOf(Map<String, dynamic>? metadata) {
  final raw = metadata?[reportedCostKey];
  final cost = raw is num ? raw.toDouble() : (raw is String ? double.tryParse(raw) : null);
  return cost == null || !cost.isFinite || cost < 0 ? null : cost;
}

/// The [reportedCostKey] entry for a provider's `cost_in_usd_ticks`, or
/// nothing when the usage block does not carry a usable one. Shared by the
/// protocols that read xAI's block so the tick unit is spelled out once.
Map<String, dynamic> reportedCostFromTicks(Object? ticks) {
  final value = ticks is num ? ticks.toDouble() : (ticks is String ? double.tryParse(ticks) : null);
  if (value == null || !value.isFinite || value < 0) return const {};
  return {reportedCostKey: value / 1e10};
}

class OutputSpec {
  final String? size;
  final String? quality;
  final int? seconds;

  const OutputSpec({this.size, this.quality, this.seconds});

  static const OutputSpec none = OutputSpec();

  /// Request values meaning "let the provider decide". They carry no spec, so
  /// only a rate row that leaves the dimension blank can match them.
  static const Set<String> _unset = {'', 'auto', 'not_set', 'adaptive'};

  factory OutputSpec.from(
    Map<String, dynamic>? options, {
    Map<String, dynamic>? metadata,
  }) {
    final size = normalizeSize(
      metadata?['output_size'] ?? options?['imageSize'] ?? options?['resolution'],
    );
    final quality = normalizeQuality(
      metadata?['output_quality'] ?? options?['quality'] ?? options?['videoQuality'],
    );
    final seconds = normalizeSeconds(
      metadata?['output_seconds'] ?? options?['seconds'],
    );
    return OutputSpec(size: size, quality: quality, seconds: seconds);
  }

  /// `1k` → `1K`, `768P` → `768p`, `1024X1024` → `1024x1024`; whitespace
  /// trimmed; unset markers → null. Relays spell these freely, and the rate
  /// table is typed by hand, so both sides go through this before comparing.
  static String? normalizeSize(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (_unset.contains(s.toLowerCase())) return null;
    final wxh = parseWxH(s);
    if (wxh != null) return '${wxh.width}x${wxh.height}';
    if (RegExp(r'^\d+(?:\.\d+)?[kK]$').hasMatch(s)) return s.toUpperCase();
    if (RegExp(r'^\d+[pP]$').hasMatch(s)) return s.toLowerCase();
    return s;
  }

  static String? normalizeQuality(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    return _unset.contains(s) ? null : s;
  }

  static int? normalizeSeconds(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw <= 0 ? null : raw.round();
    final s = raw.toString().trim().toLowerCase().replaceAll(RegExp(r's$'), '');
    final n = num.tryParse(s);
    return (n == null || n <= 0) ? null : n.round();
  }

  bool get isEmpty => size == null && quality == null && seconds == null;

  /// Compact human label: `1080p · high · 8s`, or empty for no spec.
  String get label => [
        ?size,
        ?quality,
        if (seconds != null) '${seconds}s',
      ].join(' · ');
}
