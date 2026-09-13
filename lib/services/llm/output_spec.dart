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
    if (RegExp(r'^\d+\s*[xX×]\s*\d+$').hasMatch(s)) {
      return s.replaceAll(RegExp(r'\s*[xX×]\s*'), 'x');
    }
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
