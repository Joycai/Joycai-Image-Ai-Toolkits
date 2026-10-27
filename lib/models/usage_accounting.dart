import 'dart:convert';

/// A disjoint billable quantity and its immutable USD price snapshot.
class UsageComponent {
  final String meter;
  final String category;
  final double? quantity;
  final double? price;
  final double basis;
  final String source;
  const UsageComponent({
    required this.meter,
    required this.category,
    required this.quantity,
    required this.price,
    this.basis = 1,
    this.source = 'reported',
  });
  bool get complete => quantity != null && (quantity == 0 || price != null);
  double get cost => (quantity ?? 0) * (price ?? 0) / basis;
  Map<String, dynamic> toMap() => {
    'meter': meter,
    'category': category,
    'quantity': quantity,
    'price': price,
    'basis': basis,
    'source': source,
  };
  factory UsageComponent.fromMap(Map<String, dynamic> m) => UsageComponent(
    meter: m['meter'] as String,
    category: m['category'] as String,
    quantity: (m['quantity'] as num?)?.toDouble(),
    price: (m['price'] as num?)?.toDouble(),
    basis: (m['basis'] as num?)?.toDouble() ?? 1,
    source: m['source'] as String? ?? 'unknown',
  );
}

/// Versioned accounting replaces (never adds to) legacy column arithmetic.
/// Pricing contains no credentials. Unknown historical rows stay legacy.
class UsageAccounting {
  final List<UsageComponent> components;
  final Map<String, dynamic> pricing;
  final Map<String, dynamic> quantities;
  final String status;
  final bool valid;
  final int revision;
  final String currency;
  const UsageAccounting({
    required this.components,
    required this.pricing,
    this.quantities = const {},
    this.status = 'estimated',
    this.valid = true,
    this.revision = 0,
    this.currency = 'USD',
  });
  bool get complete => valid && components.isNotEmpty && components.every((c) => c.complete);
  double get cost => components.fold(0, (sum, c) => sum + c.cost);
  double categoryCost(String category) =>
      components.where((c) => c.category == category).fold(0, (sum, c) => sum + c.cost);

  /// Compatibility counters for existing charts. Unknown quantities contribute
  /// only their known subtotal; completeness stays on this accounting record.
  Map<String, dynamic> get tokenProjection {
    double quantity(String category) => components
        .where((c) => c.category == category)
        .fold(0, (sum, c) => sum + (c.quantity ?? 0));
    double rate(String category) =>
        quantity(category) == 0 ? 0 : categoryCost(category) * 1e6 / quantity(category);
    return {
      'input_tokens': quantity('input').toInt(),
      'cache_tokens': quantity('cache').toInt(),
      'output_tokens': quantity('output').toInt(),
      'input_price': rate('input'),
      'cache_price': rate('cache'),
      'output_price': rate('output'),
    };
  }

  String encode() => jsonEncode({
    'version': 1,
    'components': components.map((c) => c.toMap()).toList(),
    'pricing': pricing,
    'quantities': quantities,
    'status': status,
    'valid': valid,
    'revision': revision,
    'currency': currency,
  });
  static UsageAccounting? decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['version'] != 1) return null;
      return UsageAccounting(
        components: (m['components'] as List)
            .map((c) => UsageComponent.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList(),
        pricing: Map<String, dynamic>.from(m['pricing'] as Map),
        quantities: Map<String, dynamic>.from(m['quantities'] as Map? ?? {}),
        status: m['status'] as String,
        valid: m['valid'] == true,
        revision: m['revision'] as int? ?? 0,
        currency: m['currency'] as String? ?? 'USD',
      );
    } catch (_) {
      return null;
    }
  }
}
