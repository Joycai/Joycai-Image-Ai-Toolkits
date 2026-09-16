import 'context_window_scale.dart';

/// The output-cap slider's scale: six preset stops at equal distances, one
/// rank.
///
/// Not the context window's nine stops — that is the input side's ladder
/// (8k–1M, where a 1M context is ordinary). Output caps live an order of
/// magnitude lower: 4k for the older models and the tighter relay defaults,
/// 8k for the common default, 16k and 32k for the Qwen generation, 64k for
/// Gemini and the Claude generation before 5, 128k for GPT-5 and Claude 5.
/// The Prompt Assistant's one delivery runs 6–8k tokens, which is why the
/// scale starts where it does.
///
/// Positions are in stop units, `0` at the first stop and [maxPosition] at
/// the last, so a stop's position is its index. The slider that draws it
/// snaps, so every position it hands back is a whole stop; [positionOf]
/// still interpolates so a typed figure off the presets rests between its
/// neighbours instead of jumping to one.
class OutputCapScale {
  const OutputCapScale._();

  /// 4k, 8k, 16k, 32k, 64k, 128k.
  static const List<int> stops = [4096, 8192, 16384, 32768, 65536, 131072];

  static double get maxPosition => (stops.length - 1).toDouble();

  /// Where [tokens] sits on the track; values outside the presets rest at
  /// the ends, as on the context scale.
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

  /// The stop nearest [position], clamped to the scale.
  static int tokensAt(double position) =>
      stops[position.clamp(0.0, maxPosition).round()];

  /// The index of the stop [tokens] is exactly, or null between stops.
  static int? stopIndexOf(int tokens) {
    final i = stops.indexOf(tokens);
    return i < 0 ? null : i;
  }

  /// A typed figure in tokens — the same grammar as the context field
  /// (digits, grouped digits, `64k` / `1m` shorthand). Null for anything else.
  static int? parse(String text) => ContextWindowScale.parse(text);

  /// A stop's tick label: `4k` … `128k`. Untranslated, like every token
  /// count the editor prints in mono.
  static String label(int tokens) => ContextWindowScale.label(tokens);
}
