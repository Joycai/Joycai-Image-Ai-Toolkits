import '../param_spec.dart';
import 'generation_value.dart';

/// Compatibility boundary around the existing size rules and vocabularies.
/// Sentinel handling lives here, never in an editor or generic JSON codec.
class GenerationParam {
  const GenerationParam(this.legacy);

  final ParamSpec legacy;
  String get key => legacy.key;

  ParamValueType get valueType =>
      legacy.valueType ??
      (legacy.control == ParamControl.slider || key == 'seconds' || key == 'maxImages'
          ? ParamValueType.integer
          : legacy.sizeRules != null
          ? ParamValueType.size
          : legacy.options.any((o) => o.value == 'on' || o.value == 'off')
          ? ParamValueType.boolean
          : ParamValueType.choice);

  GenerationValue decode(String value) {
    if (value == 'not_set') return const GenerationValue(GenerationValueKind.unset);
    if (value == 'auto') return const GenerationValue(GenerationValueKind.auto);
    if (valueType == ParamValueType.boolean) {
      if (value == 'on' || value == 'off') {
        return GenerationValue(GenerationValueKind.boolean, value == 'on');
      }
    }
    if (valueType == ParamValueType.integer) {
      final n = int.tryParse(value);
      if (n == null) throw FormatException('Invalid integer for $key');
      return GenerationValue(GenerationValueKind.integer, n);
    }
    if (valueType == ParamValueType.decimal) {
      final n = double.tryParse(value);
      if (n == null || !n.isFinite) throw FormatException('Invalid decimal for $key');
      return GenerationValue(GenerationValueKind.decimal, n);
    }
    return GenerationValue(
      valueType == ParamValueType.size ? GenerationValueKind.size : GenerationValueKind.choice,
      value,
    );
  }

  String encode(GenerationValue value) => switch (value.kind) {
    GenerationValueKind.unset => 'not_set',
    GenerationValueKind.auto => 'auto',
    GenerationValueKind.boolean => value.value == true ? 'on' : 'off',
    _ => value.value.toString(),
  };

  GenerationValue get defaultValue => decode(legacy.defaultValue);

  bool accepts(GenerationValue value) {
    final encoded = encode(value);
    if (!legacy.isValid(encoded)) return false;
    // Prevent e.g. a choice named "true" or an integer encoded as a size
    // from crossing the typed boundary merely because its text matches.
    return decode(encoded) == value;
  }
}
