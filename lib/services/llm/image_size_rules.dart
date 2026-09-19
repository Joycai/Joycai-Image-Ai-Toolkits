import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Free-size rules, per endpoint
// ---------------------------------------------------------------------------

/// The numeric constraints an endpoint puts on a free `WxH` size.
///
/// Several image endpoints accept any size inside a box rather than a list
/// (gpt-image-2, DashScope's qwen-image and wan2.7-image). The box has the
/// same four walls everywhere — an edge grid, an optional edge ceiling, a
/// proportion limit and a pixel-area range — and only the numbers differ, so
/// the rules are data: a [ParamSpec] declares its set, and the picker dialog,
/// the validator and the ratio calculator all read the same one.
class ImageSizeRules {
  /// Both edges must be a multiple of this.
  final int edgeStep;

  /// The longest edge allowed, or null when the endpoint documents none and
  /// the area and proportion limits are what bound it.
  final int? maxEdge;

  /// Long edge over short edge may not exceed this.
  final double maxRatio;

  /// Inclusive pixel-area range.
  final int minPixels;
  final int maxPixels;

  const ImageSizeRules({
    this.edgeStep = 16,
    this.maxEdge,
    required this.maxRatio,
    required this.minPixels,
    required this.maxPixels,
  });

  /// The longest edge any legal size can have: the declared ceiling, or the
  /// one the area and proportion limits imply together.
  int get longEdgeCeiling {
    final implied = math.sqrt(maxPixels * maxRatio).floor();
    final ceiling = maxEdge == null ? implied : math.min(maxEdge!, implied);
    return (ceiling ~/ edgeStep) * edgeStep;
  }

  /// Per-rule breakdown for live feedback in the picker dialog. The edge
  /// ceiling row is absent when the endpoint has none.
  List<SizeRuleResult> check(int w, int h) {
    final long = w > h ? w : h;
    final short = w > h ? h : w;
    final pixels = w * h;
    return [
      SizeRuleResult('sizeRuleMultiple16', w % edgeStep == 0 && h % edgeStep == 0),
      if (maxEdge != null) SizeRuleResult('sizeRuleMaxEdge', long <= maxEdge!),
      SizeRuleResult('sizeRuleAspect', short > 0 && (long / short) <= maxRatio),
      SizeRuleResult('sizeRulePixels', pixels >= minPixels && pixels <= maxPixels),
    ];
  }

  bool passes(int w, int h) => check(w, h).every((r) => r.passes);

  /// Whether [value] is a `WxH` string these rules accept. Keywords (`auto`,
  /// `1K`…) are not sizes and are never valid here — a spec lists those as
  /// options.
  bool isValidSize(String value) {
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
    if (match == null) return false;
    final w = int.tryParse(match.group(1)!);
    final h = int.tryParse(match.group(2)!);
    if (w == null || h == null || w <= 0 || h <= 0) return false;
    return passes(w, h);
  }

  /// Turns "this ratio, this long edge" into a legal WxH.
  ///
  /// The long edge is what the user typed, so it leads: it snaps to the
  /// nearest grid line and the short edge is then the grid line that lands
  /// closest to [spec]. Where that pair breaks one of the other rules — 1:1
  /// at 3840 is 14.7 MP, well over gpt-image-2's cap — the long edge steps
  /// outward along the grid (nearest first) until a legal pair appears.
  ///
  /// Always returns a size. When the ratio itself is out of bounds (where no
  /// pair of edges can ever be legal) it returns the straight computation, so
  /// the dialog's rule list can say which rule the request fell foul of
  /// rather than the button appearing to do nothing.
  (int, int) sizeFor(AspectRatioSpec spec, int longEdge) {
    (int, int) orient(int long, int short) => spec.portrait ? (short, long) : (long, short);

    final ceiling = longEdgeCeiling;
    final requested = _snapEdge(longEdge, edgeStep, ceiling);

    // Nearest legal long edge wins, so the whole grid is fair game: a 1:1 at
    // 3840 has to come down before it fits under a pixel cap, while a 16:9 at
    // 200 has to come *up* to clear the floor. Both corrections are shown
    // back to the user in the long-edge field.
    for (int delta = 0; delta <= ceiling; delta += edgeStep) {
      for (final long in delta == 0 ? [requested] : [requested - delta, requested + delta]) {
        if (long < edgeStep || long > ceiling) continue;
        for (final short in _shortEdgeCandidates(long, spec.longOverShort, edgeStep)) {
          final (w, h) = orient(long, short);
          if (passes(w, h)) return (w, h);
        }
      }
    }

    final fallbackShort =
        _shortEdgeCandidates(requested, spec.longOverShort, edgeStep).firstOrNull ?? edgeStep;
    return orient(requested, fallbackShort);
  }
}

/// gpt-image-2 (per OpenAI's published spec): edges on the 16 grid, longest
/// edge ≤ 3840, proportion ≤ 3:1, area in [655 360, 8 294 400] (~0.66–8.29 MP).
const kOpenAIImage2SizeRules = ImageSizeRules(
  maxEdge: 3840,
  maxRatio: 3,
  minPixels: 655360,
  maxPixels: 8294400,
);

/// `qwen-image-2.0*` / `-3.0*` / `qwen-image-edit-max|plus`: area 512²–2048²,
/// proportion 1:8–8:1, edges rounded to 16 upstream — sent already on the
/// grid so the request asks for exactly what is rendered.
const kDashscopeQwenSizeRules = ImageSizeRules(
  maxRatio: 8,
  minPixels: 512 * 512,
  maxPixels: 2048 * 2048,
);

/// `wan2.7-image`: area 768²–2048², proportion 1:8–8:1. The 16 grid is ours,
/// not documented — every size in upstream's own recommendation table sits
/// on it, so it costs nothing and cannot be the reason for a 400.
const kDashscopeWanSizeRules = ImageSizeRules(
  maxRatio: 8,
  minPixels: 768 * 768,
  maxPixels: 2048 * 2048,
);

/// `wan2.7-image-pro`: the same, with the ceiling raised to 4096².
const kDashscopeWanProSizeRules = ImageSizeRules(
  maxRatio: 8,
  minPixels: 768 * 768,
  maxPixels: 4096 * 4096,
);

// ---------------------------------------------------------------------------
// gpt-image-2 size constraints
// ---------------------------------------------------------------------------

/// Whether [value] is something gpt-image-2's size field accepts: `auto`, or
/// a `WxH` inside [kOpenAIImage2SizeRules].
bool isValidOpenAIImage2Size(String value) =>
    // The `auto` sentinel is `_openaiImage2`'s default, not a size.
    value == 'auto' || kOpenAIImage2SizeRules.isValidSize(value);

// ---------------------------------------------------------------------------
// Aspect-ratio → size calculator
// ---------------------------------------------------------------------------

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

/// [ImageSizeRules.sizeFor] under gpt-image-2's rules.
(int, int) sizeForAspectRatio(AspectRatioSpec spec, int longEdge) =>
    kOpenAIImage2SizeRules.sizeFor(spec, longEdge);

/// The grid lines bracketing `long / ratio`, nearest ratio first.
List<int> _shortEdgeCandidates(int long, double longOverShort, int step) {
  final exact = long / longOverShort;
  final lower = (exact / step).floor() * step;
  final candidates =
      <int>[lower, lower + step].where((s) => s >= step && s <= long).toList();
  double error(int s) => ((long / s) - longOverShort).abs();
  candidates.sort((a, b) => error(a).compareTo(error(b)));
  return candidates;
}

/// Nearest grid line, clamped to the legal edge range.
int _snapEdge(int raw, int step, int ceiling) {
  final clamped = raw.clamp(step, ceiling);
  final snapped = ((clamped + step ~/ 2) ~/ step) * step;
  return snapped.clamp(step, ceiling);
}

/// Per-rule breakdown for live feedback in the picker dialog. Each entry maps
/// to a localized message key consumed by the UI layer.
class SizeRuleResult {
  final String labelKey;
  final bool passes;
  const SizeRuleResult(this.labelKey, this.passes);
}

List<SizeRuleResult> checkOpenAIImage2SizeRules(int w, int h) =>
    kOpenAIImage2SizeRules.check(w, h);
