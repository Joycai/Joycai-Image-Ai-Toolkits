/// The context-window slider's scale (`D1c · 1a` / `1d`): nine preset stops
/// set at equal distances, with the value between two stops interpolated
/// linearly.
///
/// Equal spacing is the point. The presets double most of the way up, so a
/// linear track would crowd 8k to 128k into its first eighth; a log track
/// would put 96k somewhere that is not a stop. Interpolating within each
/// segment keeps every preset on a tick and still lets a typed value that is
/// not a preset (200 000) sit in proportion between its neighbours.
///
/// The stops come in two ranks (`1a`): every other one from 8k is a **major**
/// stop with a long tick and a bold label — 8k · 32k · 96k · 256k · 1M — and
/// the four between them are **minor**. The rank changes how a stop is drawn
/// and how far a ⇧-arrow jumps; the scale itself treats all nine alike.
///
/// Positions are in stop units, `0` at the first stop and [maxPosition] at
/// the last, so a stop's position is its index.
class ContextWindowScale {
  const ContextWindowScale._();

  /// 8k, 16k, 32k, 64k, 96k, 128k, 256k, 512k, 1M.
  static const List<int> stops = [
    8192,
    16384,
    32768,
    65536,
    98304,
    131072,
    262144,
    524288,
    1048576,
  ];

  /// Dragging moves the value in whole multiples of this.
  static const int step = 1024;

  /// How close to a stop, as a share of the whole track, a drag has to come
  /// before it is pulled onto the stop (`1a` 「±3% 轨长即吸附」).
  static const double magnetShare = 0.03;

  static double get maxPosition => (stops.length - 1).toDouble();

  /// Whether the stop at [index] is one of the five major rungs.
  static bool isMajor(int index) => index.isEven;

  /// Where [tokens] sits on the track. Values below the first stop sit at 0
  /// and values above the last at [maxPosition]: a typed value outside the
  /// presets is kept as typed, and the thumb simply rests at the end.
  static double positionOf(int tokens) {
    if (tokens <= stops.first) return 0;
    if (tokens >= stops.last) return maxPosition;
    var i = 0;
    while (tokens > stops[i + 1]) {
      i++;
    }
    final lo = stops[i];
    final hi = stops[i + 1];
    return i + (tokens - lo) / (hi - lo);
  }

  /// The value at [position], snapped to a whole [step] and kept within the
  /// first and last stops.
  static int tokensAt(double position) {
    final p = position.clamp(0.0, maxPosition);
    final i = p.floor();
    if (i >= stops.length - 1) return stops.last;
    final lo = stops[i];
    final hi = stops[i + 1];
    final raw = lo + (p - i) * (hi - lo);
    final snapped = (raw / step).round() * step;
    return snapped.clamp(stops.first, stops.last);
  }

  /// [position] pulled onto the nearest stop when it lies within
  /// [magnetShare] of the track's length from it, else returned as is.
  static double magnet(double position) {
    final p = position.clamp(0.0, maxPosition);
    final nearest = p.roundToDouble();
    return (p - nearest).abs() <= magnetShare * maxPosition ? nearest : p;
  }

  /// The index of the stop [tokens] is exactly, or null between stops.
  static int? stopIndexOf(int tokens) {
    final i = stops.indexOf(tokens);
    return i < 0 ? null : i;
  }

  /// The stop [direction] (+1 / −1) away from [tokens]. From between two
  /// stops it is the nearer one in that direction; with [majorOnly] the
  /// minor stops are skipped. Null at the end of the scale.
  static int? stepFrom(int tokens, int direction, {bool majorOnly = false}) {
    final p = positionOf(tokens);
    var i = direction > 0 ? (p + 1e-9).floor() + 1 : (p - 1e-9).ceil() - 1;
    // Off the scale's end the thumb rests on the end stop, but the value is
    // past it: the first step in lands on that end stop.
    if (tokens > stops.last && direction < 0) i = stops.length - 1;
    if (tokens < stops.first && direction > 0) i = 0;
    while (majorOnly && i >= 0 && i < stops.length && !isMajor(i)) {
      i += direction;
    }
    if (i < 0 || i >= stops.length) return null;
    return stops[i];
  }

  /// A typed figure in tokens: plain digits, digits grouped with spaces or
  /// commas, or the `128k` / `1m` shorthand the labels use (case-insensitive,
  /// binary thousands). Null for anything else, including a blank.
  static int? parse(String text) {
    final s = text.trim().replaceAll(RegExp(r'[\s,]'), '').toLowerCase();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d+(?:\.\d+)?)([km]?)$').firstMatch(s);
    if (m == null) return null;
    final number = double.tryParse(m.group(1)!);
    if (number == null) return null;
    final unit = switch (m.group(2)) {
      'k' => 1024,
      'm' => 1048576,
      _ => 1,
    };
    if (unit == 1 && m.group(1)!.contains('.')) return null;
    final tokens = (number * unit).round();
    return tokens < 0 ? null : tokens;
  }

  /// A stop's tick label: `8k` … `512k`, `1M`. Untranslated by intent, like
  /// every other token count the editor prints in mono.
  static String label(int tokens) =>
      tokens >= 1048576 ? '${tokens ~/ 1048576}M' : '${tokens ~/ 1024}k';
}
