// ---------------------------------------------------------------------------
// gpt-image-2 size constraints
// ---------------------------------------------------------------------------

/// Validates a `WxH` size string against OpenAI's gpt-image-2 rules. Used by
/// both the capability spec's [ParamSpec.customValidator] and the picker
/// dialog's per-edge breakdown.
///
/// Rules (per OpenAI's published gpt-image-2 spec):
///   * Both edges must be multiples of 16.
///   * Max edge ≤ 3840 px.
///   * Long-edge / short-edge ratio ≤ 3:1.
///   * Total pixels in [655_360, 8_294_400] — equivalent to ~0.66 MP–~8.29 MP.
bool isValidOpenAIImage2Size(String value) {
  // Accept the `auto` sentinel separately (used by `_openaiImage2.defaultValue`).
  if (value == 'auto') return true;
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
  if (match == null) return false;
  final w = int.tryParse(match.group(1)!);
  final h = int.tryParse(match.group(2)!);
  if (w == null || h == null || w <= 0 || h <= 0) return false;
  return checkOpenAIImage2SizeRules(w, h).every((r) => r.passes);
}

// ---------------------------------------------------------------------------
// Aspect-ratio → size calculator
// ---------------------------------------------------------------------------

/// The edge grid every gpt-image-2 size sits on.
const int kImage2EdgeStep = 16;

/// The largest edge gpt-image-2 accepts.
const int kImage2MaxEdge = 3840;

/// A parsed aspect ratio, kept as *ratio plus orientation* rather than a bare
/// number: `16:9` and `9:16` are the same shape turned on its side, and which
/// one the user typed is the only thing that says whether the long edge is the
/// width or the height. Nothing else in the dialog asks them.
class AspectRatioSpec {
  /// Long edge divided by short edge — always ≥ 1.
  final double longOverShort;

  /// True when the *height* is the long edge (`9:16`, or a decimal below 1).
  final bool portrait;

  const AspectRatioSpec(this.longOverShort, this.portrait);
}

/// Parses `16:9`, `16x9`, `16/9` or a bare decimal (`1.78`, `0.5625`).
///
/// Returns null for anything that isn't two positive numbers or one positive
/// decimal — the caller disables its button on null rather than guessing.
AspectRatioSpec? parseAspectRatio(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final pair = RegExp(r'^(\d+(?:\.\d+)?)\s*[:x×/]\s*(\d+(?:\.\d+)?)$', caseSensitive: false)
      .firstMatch(text);
  if (pair != null) {
    final a = double.parse(pair.group(1)!);
    final b = double.parse(pair.group(2)!);
    if (a <= 0 || b <= 0) return null;
    return AspectRatioSpec(a >= b ? a / b : b / a, b > a);
  }

  final single = double.tryParse(text);
  if (single == null || single <= 0) return null;
  return AspectRatioSpec(single >= 1 ? single : 1 / single, single < 1);
}

/// Writes [w]×[h] back as the shortest exact ratio it can — `3840×2160` reads
/// as `16:9`, not `1.778`. Falls back to a decimal when the reduced terms are
/// too big to be worth reading (`1000×1234` → `0.81`).
String formatAspectRatio(int w, int h) {
  if (w <= 0 || h <= 0) return '';
  int a = w, b = h;
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  final rw = w ~/ a;
  final rh = h ~/ a;
  if (rw <= 64 && rh <= 64) return '$rw:$rh';
  return (w / h).toStringAsFixed(2);
}

/// Turns "this ratio, this long edge" into a legal WxH.
///
/// The long edge is what the user typed, so it leads: it snaps to the nearest
/// multiple of 16 and the short edge is then the multiple of 16 that lands
/// closest to [spec]. Where that pair breaks one of the other three rules —
/// 1:1 at 3840 is 14.7 MP, well over the cap — the long edge steps outward
/// along the grid (nearest first) until a legal pair appears.
///
/// Always returns a size. When the ratio itself is out of bounds (past 3:1,
/// where no pair of edges can ever be legal) it returns the straight
/// computation, so the dialog's rule list can say which rule the request fell
/// foul of rather than the button appearing to do nothing.
(int, int) sizeForAspectRatio(AspectRatioSpec spec, int longEdge) {
  (int, int) orient(int long, int short) => spec.portrait ? (short, long) : (long, short);

  final requested = _snapEdge(longEdge);

  // Nearest legal long edge wins, so the whole grid is fair game: a 1:1 at
  // 3840 is 14.7 MP and has to come down to 2880 before it fits under the
  // cap, while a 16:9 at 200 has to come *up* to clear the 0.66 MP floor.
  // Both corrections are shown back to the user in the long-edge field.
  for (int delta = 0; delta <= kImage2MaxEdge; delta += kImage2EdgeStep) {
    for (final long in delta == 0 ? [requested] : [requested - delta, requested + delta]) {
      if (long < kImage2EdgeStep || long > kImage2MaxEdge) continue;
      for (final short in _shortEdgeCandidates(long, spec.longOverShort)) {
        final (w, h) = orient(long, short);
        if (checkOpenAIImage2SizeRules(w, h).every((r) => r.passes)) return (w, h);
      }
    }
  }

  final fallbackShort = _shortEdgeCandidates(requested, spec.longOverShort).firstOrNull ??
      kImage2EdgeStep;
  return orient(requested, fallbackShort);
}

/// The multiples of 16 bracketing `long / ratio`, nearest ratio first.
List<int> _shortEdgeCandidates(int long, double longOverShort) {
  final exact = long / longOverShort;
  final lower = (exact / kImage2EdgeStep).floor() * kImage2EdgeStep;
  final candidates = <int>[lower, lower + kImage2EdgeStep]
      .where((s) => s >= kImage2EdgeStep && s <= long)
      .toList();
  double error(int s) => ((long / s) - longOverShort).abs();
  candidates.sort((a, b) => error(a).compareTo(error(b)));
  return candidates;
}

/// Nearest multiple of 16, clamped to the legal edge range.
int _snapEdge(int raw) {
  final clamped = raw.clamp(kImage2EdgeStep, kImage2MaxEdge);
  final snapped =
      ((clamped + kImage2EdgeStep ~/ 2) ~/ kImage2EdgeStep) * kImage2EdgeStep;
  return snapped.clamp(kImage2EdgeStep, kImage2MaxEdge);
}

/// Per-rule breakdown for live feedback in the picker dialog. Each entry maps
/// to a localized message key consumed by the UI layer.
class SizeRuleResult {
  final String labelKey;
  final bool passes;
  const SizeRuleResult(this.labelKey, this.passes);
}

List<SizeRuleResult> checkOpenAIImage2SizeRules(int w, int h) {
  final long = w > h ? w : h;
  final short = w > h ? h : w;
  final pixels = w * h;
  return [
    SizeRuleResult('sizeRuleMultiple16', w % 16 == 0 && h % 16 == 0),
    SizeRuleResult('sizeRuleMaxEdge', long <= 3840),
    SizeRuleResult('sizeRuleAspect', short > 0 && (long / short) <= 3.0),
    SizeRuleResult(
        'sizeRulePixels', pixels >= 655360 && pixels <= 8294400),
  ];
}
