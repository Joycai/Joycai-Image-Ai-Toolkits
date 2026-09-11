/// The context-window slider's scale (`D1c · 1d`): nine preset stops set at
/// equal distances, with the value between two stops interpolated linearly.
///
/// Equal spacing is the point. The presets double most of the way up, so a
/// linear track would crowd 8k to 128k into its first eighth; a log track
/// would put 96k somewhere that is not a stop. Interpolating within each
/// segment keeps every preset on a tick and still lets a typed value that is
/// not a preset (200 000) sit in proportion between its neighbours.
///
/// Positions are in stop units, `0` at the first stop and [maxPosition] at
/// the last, so a stop's position is its index.
class ContextWindowScale {
  const ContextWindowScale._();

  /// 8k, 16k, 32k, 64k, 96k, 128k, 256k, 512k, 1M.
  static const List<int> stops = [8192, 16384, 32768, 65536, 98304, 131072, 262144, 524288, 1048576];

  /// Dragging moves the value in whole multiples of this.
  static const int step = 1024;

  static double get maxPosition => (stops.length - 1).toDouble();

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

  /// A stop's tick label: `8k` … `512k`, `1M`. Untranslated by intent, like
  /// every other token count the editor prints in mono.
  static String label(int tokens) =>
      tokens >= 1048576 ? '${tokens ~/ 1048576}M' : '${tokens ~/ 1024}k';
}
