/// How a parameter should be rendered in the workbench config UI.
///
/// `customSize` is a specialised control for image-size parameters whose set
/// of legal values isn't enumerable — the spec lists popular presets, but the
/// dialog also lets the user type any WxH that satisfies the param's
/// [ParamSpec.customValidator]. Used by gpt-image-2, where OpenAI accepts any
/// pixel dimensions meeting four numeric constraints.
///
/// `slider` is a continuous-range integer control bounded by [ParamSpec.min]
/// / [ParamSpec.max] rather than a discrete [ParamSpec.options] list. Used by
/// grok-imagine-video's duration parameter (1–15s).
enum ParamControl { dropdown, segmented, customSize, slider }

/// A single selectable option for a parameter.
///
/// [value] is what gets sent to the provider; the human-readable label is
/// resolved in the UI layer (so localization stays out of this pure-data file).
class ParamOption {
  final String value;
  const ParamOption(this.value);
}

/// Declarative spec for one configurable generation parameter.
///
/// [key] is the option key handed to the provider (e.g. `aspectRatio`,
/// `imageSize`, `quality`) and must match what the providers read from the
/// task `options` map. [labelKey] is a stable token the UI maps to a localized
/// label.
class ParamSpec {
  final String key;
  final String labelKey;
  final ParamControl control;
  final List<ParamOption> options;
  final String defaultValue;

  /// Optional predicate that accepts user-typed values outside the discrete
  /// [options] list (e.g. arbitrary WxH for gpt-image-2). When set,
  /// [isValid] returns true if the value is either a known option *or* the
  /// validator accepts it.
  ///
  /// Must be a pure / `const`-compatible top-level function so this class
  /// stays `const`-constructible.
  final bool Function(String value)? customValidator;

  /// Inclusive bounds for [ParamControl.slider]. Unused by every other
  /// control.
  final int? min;
  final int? max;

  const ParamSpec({
    required this.key,
    required this.labelKey,
    required this.control,
    required this.options,
    required this.defaultValue,
    this.customValidator,
    this.min,
    this.max,
  });

  bool isValid(String? value) {
    if (value == null) return false;
    if (options.any((o) => o.value == value)) return true;
    // A slider has no discrete [options] — its valid set is the range it
    // already declares. Without this branch every slider value failed both
    // checks below, so [normalize] handed back [defaultValue] forever: the
    // control snapped back on the next rebuild and the request carried the
    // default no matter what the user chose. The one slider that worked did
    // so only because it carried a hand-written validator restating its own
    // min/max.
    //
    // The bounds fall back to the same 1/15 the panel clamps with, so a value
    // this accepts is always one the control can actually render — the two
    // must not be able to disagree about what is in range.
    if (control == ParamControl.slider) {
      final n = int.tryParse(value);
      if (n == null) return false;
      return n >= (min ?? 1) && n <= (max ?? 15);
    }
    final validator = customValidator;
    return validator != null && validator(value);
  }

  /// Returns [value] when it is a valid option for this spec, otherwise the
  /// default. Guarantees the UI never tries to render an out-of-range value
  /// and the provider never receives one (important when switching families).
  String normalize(String? value) => isValid(value) ? value! : defaultValue;
}
