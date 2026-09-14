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
    if (RegExp(r'^\d+[kK]$').hasMatch(s)) return s.toUpperCase();
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

  Map<String, dynamic> toJson() => {
        if (size != null) 'size': size,
        if (quality != null) 'quality': quality,
        if (seconds != null) 'seconds': seconds,
      };

  /// Compact human label: `1080p · high · 8s`, or empty for no spec.
  String get label => [
        ?size,
        ?quality,
        if (seconds != null) '${seconds}s',
      ].join(' · ');
}
