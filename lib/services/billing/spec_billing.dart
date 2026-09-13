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
SpecRateMatch matchSpecRate(List<SpecRate> rates, OutputSpec spec) {
  SpecRate? best;
  for (final rate in rates) {
    if (rate.size != null && rate.size != spec.size) continue;
    if (rate.quality != null && rate.quality != spec.quality) continue;
    if (rate.seconds != null && rate.seconds != spec.seconds) continue;
    if (best == null || rate.specificity > best.specificity) best = rate;
  }
  return SpecRateMatch(best);
}

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
