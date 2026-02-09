class FeeGroup {
  final int? id;
  final String name;
  final String billingMode; // token, request
  final double inputPrice;
  final double outputPrice;
  final double requestPrice;

  FeeGroup({
    this.id,
    required this.name,
    this.billingMode = 'token',
    this.inputPrice = 0.0,
    this.outputPrice = 0.0,
    this.requestPrice = 0.0,
  });

  factory FeeGroup.fromMap(Map<String, dynamic> map) {
    return FeeGroup(
      id: map['id'] as int?,
      name: map['name'] as String,
      billingMode: map['billing_mode'] as String? ?? 'token',
      inputPrice: (map['input_price'] ?? 0.0) as double,
      outputPrice: (map['output_price'] ?? 0.0) as double,
      requestPrice: (map['request_price'] ?? 0.0) as double,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'billing_mode': billingMode,
      'input_price': inputPrice,
      'output_price': outputPrice,
      'request_price': requestPrice,
    };
  }
}
