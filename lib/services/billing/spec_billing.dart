import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/spec_rate.dart';
import '../../models/token_usage.dart';
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
    final better =
        best == null ||
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

  /// Reference images the request sent, how many of them are charged once
  /// the group's free ones are off, and the price of each.
  final int inputImages;
  final double inputUnits;
  final double inputUnitPrice;

  const SpecUsage({
    required this.unit,
    required this.units,
    required this.unitPrice,
    required this.spec,
    required this.matched,
    this.inputImages = 0,
    this.inputUnits = 0.0,
    this.inputUnitPrice = 0.0,
  });

  /// Output and input together.
  double get cost => units * unitPrice + inputUnits * inputUnitPrice;

  /// What this leaves on the usage row. The snapshot keeps the spec plus
  /// whether a row priced it, so the usage page can count the requests a rate
  /// table failed to cover.
  UsageSpecBilling toBilling() => UsageSpecBilling(
    unit: unit,
    units: units,
    unitPrice: unitPrice,
    snapshot: UsageSpecSnapshot(
      size: spec.size,
      quality: spec.quality,
      seconds: spec.seconds,
      matched: matched,
    ),
    inputImages: inputImages,
    inputUnits: inputUnits,
    inputUnitPrice: inputUnitPrice,
  );

  /// Prices one request against a group's table. [imageCount] is what the
  /// response actually carried; seconds come from the spec (the request),
  /// since no provider reports the length it rendered.
  ///
  /// The input side: [inputImageCount] reference images went out, the first
  /// [inputFreeUnits] of them are free (per request — Seedream 5.0 pro's
  /// 「首张免费」), the rest cost [inputUnitPrice] each. A request that
  /// delivered nothing — zero units — is not charged for what it sent
  /// either: Ark says outright that a failed generation is free, and a
  /// picture-less reply on any other route is the same non-event. Every
  /// unit charges them (`D2e`): a per-second or per-clip group prices a
  /// video's first frame and reference images exactly as a per-image group
  /// prices an edit's — xAI bills \$0.01 a frame beside its per-second rate,
  /// and the video surfaces publish what they sent ([VideoSubmission]).
  /// A group that does not charge inputs bills zero of them at a price of
  /// zero, so its rows stay as quiet as they were. The count sent and the
  /// group's price are kept regardless — a request whose only image was the
  /// free one still says so on the usage page.
  static SpecUsage price({
    required OutputUnit unit,
    required List<SpecRate> rates,
    required OutputSpec spec,
    required int imageCount,
    int inputImageCount = 0,
    double inputUnitPrice = 0.0,
    int inputFreeUnits = 0,
  }) {
    final match = matchSpecRate(rates, spec);
    final double units = switch (unit) {
      OutputUnit.image => imageCount.toDouble(),
      OutputUnit.second => (spec.seconds ?? 0).toDouble(),
      OutputUnit.clip => 1.0,
    };
    final inputs = chargedInputImages(
      sent: inputImageCount,
      unitPrice: inputUnitPrice,
      freeUnits: inputFreeUnits,
      delivered: units > 0,
    );
    return SpecUsage(
      unit: unit,
      units: units,
      unitPrice: match.price,
      spec: spec,
      matched: match.matched,
      inputImages: inputs.inputImages,
      inputUnits: inputs.inputUnits,
      inputUnitPrice: inputs.inputUnitPrice,
    );
  }

  /// The input side alone, for a request-billed group: the three input
  /// columns of the usage row, with the output four left empty. A
  /// request-billed group charges its request price whatever came back, so
  /// its inputs count as delivered too. Null when the group charges no
  /// inputs or the request sent none — the row then reads exactly as a
  /// request-billed row always has.
  static UsageSpecBilling? inputsOnly({
    required int inputImageCount,
    required double inputUnitPrice,
    required int inputFreeUnits,
  }) {
    if (inputUnitPrice <= 0 || inputImageCount <= 0) return null;
    return chargedInputImages(
      sent: inputImageCount,
      unitPrice: inputUnitPrice,
      freeUnits: inputFreeUnits,
      delivered: true,
    );
  }

  /// The input three of a usage row: [sent] images, the first [freeUnits]
  /// free, the rest at [unitPrice] — and none at all when nothing was
  /// [delivered] or the group's price is zero. Output four empty; callers
  /// that price outputs copy the three across.
  @visibleForTesting
  static UsageSpecBilling chargedInputImages({
    required int sent,
    required double unitPrice,
    required int freeUnits,
    required bool delivered,
  }) {
    final images = math.max(0, sent);
    final charges = unitPrice > 0;
    final charged = charges && delivered ? math.max(0, images - math.max(0, freeUnits)) : 0;
    return UsageSpecBilling(
      units: 0.0,
      unitPrice: 0.0,
      inputImages: images,
      inputUnits: charged.toDouble(),
      inputUnitPrice: charges ? unitPrice : 0.0,
    );
  }
}
