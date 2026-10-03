/// Semantic values are independent of UI editors and wire sentinel spelling.
enum GenerationValueKind { unset, auto, boolean, integer, decimal, choice, size }

class GenerationValue {
  const GenerationValue(this.kind, [this.value]);

  final GenerationValueKind kind;
  final Object? value;

  Map<String, dynamic> toJson() => {'kind': kind.name, if (value != null) 'value': value};

  factory GenerationValue.fromJson(Map<String, dynamic> json) {
    final kind = GenerationValueKind.values.byName(json['kind'] as String);
    final value = json['value'];
    final valid = switch (kind) {
      GenerationValueKind.unset || GenerationValueKind.auto => value == null,
      GenerationValueKind.boolean => value is bool,
      GenerationValueKind.integer => value is int,
      GenerationValueKind.decimal => value is num && value.isFinite,
      GenerationValueKind.choice || GenerationValueKind.size => value is String,
    };
    if (!valid) throw FormatException('Invalid ${kind.name} generation value');
    return GenerationValue(kind, value);
  }

  @override
  bool operator ==(Object other) =>
      other is GenerationValue && kind == other.kind && value == other.value;

  @override
  int get hashCode => Object.hash(kind, value);
}
