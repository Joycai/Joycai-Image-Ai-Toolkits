import 'spec_rate.dart';

class PricingGroup {
  final int? id;
  final String name;
  final String billingMode; // token, request, spec
  final double inputPrice;

  /// Price for input tokens served from the provider's prompt cache.
  ///
  /// Null means "not configured": cache hits are then billed at [inputPrice].
  /// Kept nullable rather than defaulting to 0 so a genuinely free cache (0.0)
  /// stays distinguishable from an unset field.
  final double? cacheInputPrice;

  final double outputPrice;
  final double requestPrice;

  /// Spec billing (`billing_mode == 'spec'`): what one request counts as,
  /// and the rate table matched against the request's output spec. Ignored
  /// by the other two modes, kept through edits like the other modes' rates.
  final OutputUnit outputUnit;
  final List<SpecRate> outputRates;

  PricingGroup({
    this.id,
    required this.name,
    this.billingMode = 'token',
    this.inputPrice = 0.0,
    this.cacheInputPrice,
    this.outputPrice = 0.0,
    this.requestPrice = 0.0,
    this.outputUnit = OutputUnit.image,
    this.outputRates = const [],
  });

  /// Price actually charged per cached input token.
  double get effectiveCacheInputPrice => cacheInputPrice ?? inputPrice;

  bool get isSpecBilled => billingMode == 'spec';

  factory PricingGroup.fromMap(Map<String, dynamic> map) {
    return PricingGroup(
      id: map['id'] as int?,
      name: map['name'] as String,
      billingMode: map['billing_mode'] as String? ?? 'token',
      inputPrice: (map['input_price'] as num? ?? 0.0).toDouble(),
      cacheInputPrice: (map['cache_input_price'] as num?)?.toDouble(),
      outputPrice: (map['output_price'] as num? ?? 0.0).toDouble(),
      requestPrice: (map['request_price'] as num? ?? 0.0).toDouble(),
      outputUnit: OutputUnit.parse(map['output_unit'] as String?),
      outputRates: SpecRate.decodeList(map['output_rates'] as String?),
    );
  }

  Map<String, dynamic> toMap({bool includeId = true}) {
    final Map<String, dynamic> data = {
      'name': name,
      'billing_mode': billingMode,
      'input_price': inputPrice,
      'cache_input_price': cacheInputPrice,
      'output_price': outputPrice,
      'request_price': requestPrice,
      'output_unit': outputUnit.name,
      'output_rates': SpecRate.encodeList(outputRates),
    };
    if (includeId) {
      data['id'] = id;
    }
    return data;
  }
}
