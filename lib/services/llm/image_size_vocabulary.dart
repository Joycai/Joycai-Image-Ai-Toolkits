import 'dart:math' as math;

import 'image_size_rules.dart';
import 'output_spec.dart';

/// What a model's "no size chosen" value means — the one line the size
/// picker says about it (`A1c · 30a`). Not the same thing in every family,
/// and the copy must not pretend it is.
enum SizeSentinelMeaning {
  /// `auto`: the model picks (gpt-image-2).
  modelDecides,

  /// `not_set` on qwen: the app sends a 1K-area size — a 1024² square for
  /// text-to-image, the input's proportions fitted into the 1K area for an
  /// edit (`dashscopeQwenDefaultSize`).
  followsInput,

  /// `not_set` on wan: the app sends the `1K` keyword.
  sendsLowestTier,
}

/// How the picker's tier segments (`1K` / `2K` / `4K`) turn into a value.
enum SizeTierKind {
  /// wan: the tier is a keyword the endpoint takes. At 1:1 the keyword itself
  /// is submitted; at any other ratio the tier's pixels are.
  keyword,

  /// qwen: an area tier the endpoint bills by — the tier's pixels at the
  /// chosen ratio, within the tier's area.
  areaTier,

  /// gpt-image-2: an area *target*, not a keyword — the largest legal size at
  /// that area or under the model's cap.
  areaTarget,
}

/// The picker's vocabulary for one model: which ratio chips and tier
/// segments it offers, what its sentinel means, and — for wan only —
/// upstream's own "ratio × tier" table.
///
/// This is the *offer*, not the constraint: what a size may be is
/// [ImageSizeRules]. Declared on the size [ParamSpec] beside the rules, in
/// layer 3, so the picker never has to recognise a model.
class ImageSizeVocabulary {
  /// Ratio chips, landscape-first as written (`16:9`, then `9:16`). The
  /// picker always ends the row with its own "custom" chip.
  final List<String> ratios;

  /// Tier segments, smallest first. The picker ends the row with "custom".
  final List<String> tiers;

  final SizeTierKind tierKind;
  final SizeSentinelMeaning sentinel;

  /// Upstream's recommendation table, tier → landscape ratio → `WxH`
  /// (wan2.7-image, text-to-image guide). Portrait ratios are the same entry
  /// turned on its side. Empty where upstream publishes none — qwen's 1K
  /// sizes are computed, and gpt has no table.
  final Map<String, Map<String, String>> officialTable;

  const ImageSizeVocabulary({
    required this.ratios,
    required this.tiers,
    required this.tierKind,
    required this.sentinel,
    this.officialTable = const {},
  });

  bool get hasOfficialTable => officialTable.isNotEmpty;
}

/// The value a size field holds, sorted into the three kinds it can be.
sealed class SizeValue {
  const SizeValue();

  /// Reads [raw] against [sentinel] — the one sentinel spelling this model
  /// uses (`auto` or `not_set`) — and [tiers].
  factory SizeValue.parse(String raw, {required String? sentinel, required List<String> tiers}) {
    if (raw == sentinel) return SizeSentinelValue(raw);
    final upper = raw.toUpperCase();
    for (final t in tiers) {
      if (t.toUpperCase() == upper) return SizeTierValue(t);
    }
    final wxh = parseWxH(raw);
    if (wxh != null) return SizeDimsValue(wxh.width, wxh.height);
    return SizeSentinelValue(raw);
  }
}

class SizeSentinelValue extends SizeValue {
  final String raw;
  const SizeSentinelValue(this.raw);
}

class SizeTierValue extends SizeValue {
  final String tier;
  const SizeTierValue(this.tier);
}

class SizeDimsValue extends SizeValue {
  final int width;
  final int height;
  const SizeDimsValue(this.width, this.height);

  String get wire => '${width}x$height';
}

/// The long-edge pixels a tier keyword stands for: `NK` → N·1024.
int? tierEdge(String tier) {
  final m = RegExp(r'^(\d+(?:\.\d+)?)[kK]$').firstMatch(tier.trim());
  if (m == null) return null;
  return (double.parse(m.group(1)!) * 1024).round();
}

/// The pixels a tier keyword renders on its own (wan: `2K` is 2048²).
({int width, int height})? keywordSquare(String tier) {
  final edge = tierEdge(tier);
  return edge == null ? null : (width: edge, height: edge);
}

/// The size a (ratio, tier) cell stands for under [rules] and [vocab].
///
/// wan takes upstream's table where it has the cell. Everywhere else the
/// tier is an area — (N·1024)², capped by the model's own area and edge
/// limits — and the size is the largest one on the model's grid at exactly
/// that ratio and within that area, when one comes within 15% of it
/// (`4:3` at 1K is 1152×864, `1:1` at gpt's 4K is 2880×2880). A ratio with no
/// such point (`1.78`, or 16:9 where the exact lattice falls short) takes the
/// nearest legal size instead (`ImageSizeRules.sizeFor`).
(int, int) tierSize(
  AspectRatioSpec ratio,
  String tier,
  ImageSizeRules rules,
  ImageSizeVocabulary vocab,
) {
  final table = vocab.officialTable[tier];
  if (table != null) {
    for (final entry in table.entries) {
      final r = parseAspectRatio(entry.key);
      final wxh = parseWxH(entry.value);
      if (r == null || wxh == null) continue;
      if ((r.longOverShort - ratio.longOverShort).abs() > 1e-6) continue;
      final long = math.max(wxh.width, wxh.height);
      final short = math.min(wxh.width, wxh.height);
      return ratio.portrait ? (short, long) : (long, short);
    }
  }

  final edge = tierEdge(tier) ?? 1024;
  final area = math.min(edge * edge, rules.maxPixels);
  final lattice = _latticeSize(ratio, area, rules);
  if (lattice != null && lattice.$1 * lattice.$2 >= area * 0.85) return lattice;
  final long = math.sqrt(area * ratio.longOverShort).round();
  return rules.sizeFor(ratio, long);
}

/// The largest legal grid point at exactly [ratio] with area ≤ [area], or
/// null when the ratio has no small-integer form or no legal point.
(int, int)? _latticeSize(AspectRatioSpec ratio, int area, ImageSizeRules rules) {
  final terms = _smallTerms(ratio.longOverShort);
  if (terms == null) return null;
  final (a, b) = terms; // long : short
  // Both edges on the grid: long = a·k, short = b·k, with k a multiple of
  // step / gcd(step, b) … simplest to walk k over the grid of the short edge.
  final step = rules.edgeStep;
  final unit = _lcm(step ~/ _gcd(step, a), step ~/ _gcd(step, b));
  final ceiling = rules.longEdgeCeiling;
  var k = unit * (math.sqrt(area / (a * b)) / unit).floor();
  for (; k >= unit; k -= unit) {
    final long = a * k;
    final short = b * k;
    if (long > ceiling || long * short > area) continue;
    if (!rules.passes(long, short)) return null;
    return ratio.portrait ? (short, long) : (long, short);
  }
  return null;
}

/// `longOverShort` as `a:b` with both terms ≤ 64, when it is one exactly.
(int, int)? _smallTerms(double longOverShort) {
  for (var b = 1; b <= 64; b++) {
    final a = longOverShort * b;
    final rounded = a.round();
    if (rounded <= 64 && (a - rounded).abs() < 1e-6) return (rounded, b);
  }
  return null;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
int _lcm(int a, int b) => a ~/ _gcd(a, b) * b;

/// The value a (ratio, tier) choice submits: the keyword itself for a wan
/// square, the cell's pixels otherwise.
String tierValue(
  AspectRatioSpec ratio,
  String tier,
  ImageSizeRules rules,
  ImageSizeVocabulary vocab,
) {
  if (vocab.tierKind == SizeTierKind.keyword && (ratio.longOverShort - 1).abs() < 1e-9) {
    return tier;
  }
  final (w, h) = tierSize(ratio, tier, rules, vocab);
  return '${w}x$h';
}

/// Which tier segment [w]×[h] is, at [ratio]: the tier whose cell is exactly
/// this size, or null ("custom").
String? tierOfSize(
  int w,
  int h,
  AspectRatioSpec? ratio,
  ImageSizeRules rules,
  ImageSizeVocabulary vocab,
) {
  final r = ratio ?? ratioOf(w, h);
  for (final t in vocab.tiers) {
    final (tw, th) = tierSize(r, t, rules, vocab);
    if (tw == w && th == h) return t;
  }
  return null;
}

/// The ratio [w]×[h] is, as the picker reasons with it.
AspectRatioSpec ratioOf(int w, int h) => AspectRatioSpec(w >= h ? w / h : h / w, h > w);

/// How a ratio reads: a chip's own label when it is one of [chips] (either
/// orientation as written), else two decimals `w/h:1` (`2.50:1`, `0.80:1`) —
/// `A1c · 30f`: 「派生比例保持 mono 两位小数，不强行凑成整数比」. A ratio the user
/// *typed* keeps its own spelling; that is the picker's to remember, not this.
String ratioLabel(int w, int h, {List<String> chips = const []}) {
  final chip = nearestChip(ratioOf(w, h), chips);
  if (chip != null) return chip;
  final v = w / h;
  // A whole number reads as one (`10:1`); anything else keeps two places.
  return v == v.roundToDouble() ? '${v.round()}:1' : '${v.toStringAsFixed(2)}:1';
}

/// The chip among [chips] that [r] is, within 3% — upstream's own "16:9"
/// cells are only near it (2688×1536 is 1.75, 2368×1728 is 2.8% off 4:3),
/// and they must still read as the chip they are listed under.
String? nearestChip(AspectRatioSpec r, List<String> chips) {
  String? best;
  var bestError = 0.03;
  for (final c in chips) {
    final cr = parseAspectRatio(c);
    if (cr == null) continue;
    if (cr.longOverShort != 1 && r.longOverShort != 1 && cr.portrait != r.portrait) continue;
    final error = (cr.longOverShort - r.longOverShort).abs() / cr.longOverShort;
    if (error <= bestError) {
      best = c;
      bestError = error;
    }
  }
  return best;
}

/// A one-click correction for an illegal size: what to set, and the label
/// the button carries (`改成 {value}`).
class SizeFix {
  /// A size to set, or — when the ratio itself is past the model's limit
  /// and was typed as a ratio — null, with [ratio] set instead.
  final (int, int)? size;

  /// The limit ratio to switch to (`3:1`), for a ratio no size can satisfy.
  final String? ratio;

  const SizeFix.size(int w, int h) : size = (w, h), ratio = null;
  const SizeFix.ratio(String this.ratio) : size = null;

  String get label => ratio ?? '${size!.$1} × ${size!.$2}';
}

/// The nearest legal answer to [w]×[h] under [rules] (`A1c · 30f`: 「保住较小
/// 那边、压回上限」). Past the proportion limit the smaller edge is kept and
/// the longer pressed back to the limit on the grid; any other violation
/// keeps the proportion and walks the long edge to the nearest legal size.
SizeFix fixFor(int w, int h, ImageSizeRules rules) {
  final long = math.max(w, h);
  final short = math.max(1, math.min(w, h));
  final portrait = h > w;
  if (long / short > rules.maxRatio) {
    final step = rules.edgeStep;
    final s = rules.snapEdge(short);
    final l = ((s * rules.maxRatio) ~/ step) * step;
    var candidate = portrait ? (s, l) : (l, s);
    if (!rules.passes(candidate.$1, candidate.$2)) {
      candidate = rules.sizeFor(AspectRatioSpec(rules.maxRatio, portrait), l);
    }
    return SizeFix.size(candidate.$1, candidate.$2);
  }
  final (fw, fh) = rules.sizeFor(ratioOf(w, h), long);
  return SizeFix.size(fw, fh);
}

/// The limit ratio as a chip would write it: `3:1`, `8:1`.
String maxRatioLabel(ImageSizeRules rules) {
  final v = rules.maxRatio;
  return v == v.roundToDouble() ? '${v.round()}:1' : '${v.toStringAsFixed(2)}:1';
}

/// Megapixels as the picker writes them: two decimals.
String megapixels(int pixels) => (pixels / 1000000).toStringAsFixed(2);

/// The edge of the square whose area is the model's ceiling — the preview's
/// "area reference" (`面积参考 2880²`), rounded to the grid.
int areaReferenceEdge(ImageSizeRules rules) {
  final edge = math.sqrt(rules.maxPixels).floor();
  return (edge ~/ rules.edgeStep) * rules.edgeStep;
}
