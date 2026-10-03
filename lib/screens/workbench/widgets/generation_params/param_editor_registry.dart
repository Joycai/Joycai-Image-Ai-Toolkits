import 'package:flutter/material.dart';

import '../../../../core/app_theme.dart';
import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/spec_rate.dart';
import '../../../../services/llm/generation/generation_param.dart';
import '../../../../services/llm/generation/generation_value.dart';
import '../../../../services/llm/param_spec.dart';
import '../../../../widgets/ui/app_dropdown.dart';
import '../../../../widgets/ui/app_field_size.dart';
import '../../../../widgets/ui/app_segmented_control.dart';
import '../size_picker/size_field.dart';

typedef ParamEditorBuilder = Widget Function(BuildContext context, ParamEditorData data);

/// All editor input is supplied by the form. Editors never read app state,
/// model IDs, providers or persistence.
class ParamEditorData {
  const ParamEditorData({
    required this.param,
    required this.value,
    required this.optionLabel,
    required this.onChanged,
    this.modelName = '',
    this.storedValue,
    this.rates,
    this.editor,
  });
  final GenerationParam param;
  final GenerationValue value;
  final String Function(String) optionLabel;
  final ValueChanged<GenerationValue> onChanged;
  final String modelName;
  final String? storedValue;
  final List<SpecRate>? rates;
  final ParamControl? editor;

  String get legacyValue => param.encode(value);
  void change(String value) => onChanged(param.decode(value));
}

/// Explicit immutable registry: a host can replace one editor without
/// copying either form or changing a semantic parameter type.
class ParamEditorRegistry {
  const ParamEditorRegistry(this.builders);
  final Map<ParamControl, ParamEditorBuilder> builders;

  static const standard = ParamEditorRegistry({
    ParamControl.dropdown: _dropdown,
    ParamControl.segmented: _segmented,
    ParamControl.slider: _slider,
    ParamControl.customSize: _size,
  });

  Widget build(BuildContext context, ParamEditorData data) {
    final builder = builders[data.editor ?? data.param.legacy.control];
    if (builder == null) {
      return Text(
        AppLocalizations.of(context)!.generationMissingEditor,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
      );
    }
    return builder(context, data);
  }
}

Widget _dropdown(BuildContext context, ParamEditorData data) => AppDropdown<String>(
  size: AppFieldSize.regular,
  value: data.legacyValue,
  items: [
    for (final option in data.param.legacy.options)
      AppDropdownItem(value: option.value, label: data.optionLabel(option.value)),
  ],
  onChanged: (value) {
    if (value != null) data.change(value);
  },
);

Widget _segmented(BuildContext context, ParamEditorData data) => AppSegmentedControl<String>(
  segments: [
    for (final option in data.param.legacy.options)
      AppSegment(value: option.value, label: data.optionLabel(option.value)),
  ],
  value: data.legacyValue,
  onChanged: data.change,
  compact: true,
  expand: true,
  tightLabels: true,
  style: AppSegmentStyle.raised,
);

Widget _size(BuildContext context, ParamEditorData data) => SizeField(
  spec: data.param.legacy,
  value: data.legacyValue,
  modelName: data.modelName,
  storedValue: data.storedValue,
  rates: data.rates,
  onChanged: data.change,
);

Widget _slider(BuildContext context, ParamEditorData data) {
  final spec = data.param.legacy;
  final lo = spec.min ?? 1;
  final hi = spec.max ?? 15;
  final value = (data.value.value as int).clamp(lo, hi);
  final text = data.optionLabel(value.toString());
  return SizedBox(
    height: AppSize.control,
    child: Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(
              context,
            ).copyWith(overlayShape: const RoundSliderOverlayShape(overlayRadius: 12)),
            child: Slider(
              value: value.toDouble(),
              min: lo.toDouble(),
              max: hi.toDouble(),
              divisions: hi > lo ? hi - lo : null,
              label: text,
              onChanged: hi > lo ? (v) => data.change(v.round().toString()) : null,
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.mono.copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ],
    ),
  );
}
