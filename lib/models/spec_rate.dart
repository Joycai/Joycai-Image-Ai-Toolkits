import 'dart:convert';

/// What a spec-billed fee group counts: pictures returned, seconds of video
/// requested, or one per job.
enum OutputUnit {
  image,
  second,
  clip;

  static OutputUnit parse(String? raw) => OutputUnit.values.firstWhere(
        (u) => u.name == raw,
        orElse: () => OutputUnit.image,
      );
}

/// One row of a spec-billed fee group's rate table: a price, and the output
/// spec it applies to. Every condition is optional; a null condition matches
/// anything, and the row with no conditions at all is the group's catch-all.
///
/// Conditions are stored already normalised (see [OutputSpec.normalizeSize] and
/// friends) so that matching is a plain equality.
class SpecRate {
  final String? size;
  final String? quality;
  final int? seconds;
  final double price;

  const SpecRate({this.size, this.quality, this.seconds, this.price = 0.0});

  /// How many conditions this row asks for — the tiebreak when several rows
  /// match one spec: the most specific wins.
  int get specificity =>
      (size != null ? 1 : 0) + (quality != null ? 1 : 0) + (seconds != null ? 1 : 0);

  bool get isCatchAll => specificity == 0;

  /// True when [other] would match exactly the same specs — two such rows in
  /// one table is a configuration error the editor rejects.
  bool sameConditionsAs(SpecRate other) =>
      size == other.size && quality == other.quality && seconds == other.seconds;

  Map<String, dynamic> toJson() => {
        if (size != null) 'size': size,
        if (quality != null) 'quality': quality,
        if (seconds != null) 'seconds': seconds,
        'price': price,
      };

  factory SpecRate.fromJson(Map<String, dynamic> json) {
    final rawSeconds = json['seconds'];
    return SpecRate(
      size: _nonEmpty(json['size']),
      quality: _nonEmpty(json['quality']),
      seconds: rawSeconds is num
          ? rawSeconds.toInt()
          : int.tryParse(rawSeconds?.toString() ?? ''),
      price: (json['price'] as num? ?? 0.0).toDouble(),
    );
  }

  static String? _nonEmpty(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Encodes a table as the JSON text stored in `fee_groups.output_rates`.
  static String encodeList(List<SpecRate> rates) =>
      jsonEncode(rates.map((r) => r.toJson()).toList());

  /// Decodes `fee_groups.output_rates`; null, blank or malformed text is an
  /// empty table rather than an error — a group with no rows bills zero,
  /// which the usage page reports as unmatched rather than crashing on load.
  static List<SpecRate> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => SpecRate.fromJson(m.cast<String, dynamic>()))
          .toList();
    } on FormatException {
      return const [];
    }
  }
}
