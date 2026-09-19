import 'dart:math' as math;

import '../../models/spec_rate.dart';
import '../llm/output_spec.dart';

/// The `billing_mode` value of a fee group priced by output spec.
const String specBillingMode = 'spec';

/// Which rate row a spec landed on, or none.
class SpecRateMatch {
  final SpecRate? rate;

  const SpecRateMatch(this.rate);

  bool get matched => rate != null;
  double get price => rate?.price ?? 0.0;
}

/// Picks the row of [rates] that prices [spec].
///
/// A row matches when every condition it states equals the spec's value — a
/// blank condition matches anything, including a spec that has no value
/// there. Of the rows that match, the one stating the most conditions wins,
/// so `1080p + high` beats `1080p` beats the catch-all without the user
/// ordering anything; among equally specific rows the earlier one wins.
///
/// One size condition is looser than equality: a resolution tier (`1K`,
/// `2K`, `4K`, `1.5K`…) also prices a pixel size that falls in that tier —
/// see [specRateTierOf]. Endpoints that take free sizes (qwen-image, wan2.7-image,
/// Seedream) bill by tier and echo the pixels they rendered, so a table
/// written in tiers must still land. An exact pixel row, where one exists,
/// beats the tier row at the same specificity.
SpecRateMatch matchSpecRate(List<SpecRate> rates, OutputSpec spec) {
  final tier = specRateTierOf(spec.size, rates);
  SpecRate? best;
  var bestExact = false;
  for (final rate in rates) {
    var exact = true;
    if (rate.size != null && rate.size != spec.size) {
      if (tier == null || rate.size != tier) continue;
      exact = false;
    }
    if (rate.quality != null && rate.quality != spec.quality) continue;
    if (rate.seconds != null && rate.seconds != spec.seconds) continue;
    final better = best == null ||
        rate.specificity > best.specificity ||
        (rate.specificity == best.specificity && exact && !bestExact);
    if (better) {
      best = rate;
      bestExact = exact;
    }
  }
  return SpecRateMatch(best);
}

/// The tier among [rates]' own tier rows that a `WxH` [size] falls in, or
/// null when [size] is not a pixel size or the table names no tier.
///
/// A tier `NK` stands for an area of (N·1024)²; the size takes the tier
/// whose area is nearest on a log scale. That puts upstream's own
/// recommendations where upstream bills them — wan's 1K-tier 16:9,
/// 1696×960 (1.63 MP), is nearer 1K (1.05 MP) than 2K (4.19 MP), and its
/// 2K-tier 2688×1536 (4.13 MP) lands on 2K — without a boundary table per
/// vendor. Only the tiers the table actually prices compete, so a table
/// with a `1.5K` row splits 1K and 2K where that vendor does.
String? specRateTierOf(String? size, List<SpecRate> rates) {
  final wxh = parseWxH(size);
  if (wxh == null) return null;
  final area = (wxh.width * wxh.height).toDouble();
  String? best;
  var bestDistance = double.infinity;
  for (final rate in rates) {
    final label = rate.size;
    if (label == null) continue;
    final m = _tierPattern.firstMatch(label);
    if (m == null) continue;
    final edge = double.parse(m.group(1)!) * 1024;
    final distance = math.log(area / (edge * edge)).abs();
    if (distance < bestDistance) {
      best = label;
      bestDistance = distance;
    }
  }
  return best;
}

final _tierPattern = RegExp(r'^(\d+(?:\.\d+)?)K$');

/// What one spec-billed request writes onto its usage row.
class SpecUsage {
  final OutputUnit unit;

  /// Pictures returned, seconds requested, or 1 — see [OutputUnit].
  final double units;
  final double unitPrice;
  final OutputSpec spec;
  final bool matched;

  const SpecUsage({
    required this.unit,
    required this.units,
    required this.unitPrice,
    required this.spec,
    required this.matched,
  });

  double get cost => units * unitPrice;

  /// The `output_spec` column: the spec plus whether a row priced it, so the
  /// usage page can count the requests a rate table failed to cover.
  Map<String, dynamic> toJson() => {...spec.toJson(), 'matched': matched};

  /// Prices one request against a group's table. [imageCount] is what the
  /// response actually carried; seconds come from the spec (the request),
  /// since no provider reports the length it rendered.
  static SpecUsage price({
    required OutputUnit unit,
    required List<SpecRate> rates,
    required OutputSpec spec,
    required int imageCount,
  }) {
    final match = matchSpecRate(rates, spec);
    final double units = switch (unit) {
      OutputUnit.image => imageCount.toDouble(),
      OutputUnit.second => (spec.seconds ?? 0).toDouble(),
      OutputUnit.clip => 1.0,
    };
    return SpecUsage(
      unit: unit,
      units: units,
      unitPrice: match.price,
      spec: spec,
      matched: match.matched,
    );
  }
}
