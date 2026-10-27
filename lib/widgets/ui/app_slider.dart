import 'package:flutter/material.dart';

/// The app slider uses the theme's track, thumb, accent and disabled colors.
/// Keep native focus, keyboard increments and accessibility semantics inside
/// this primitive, rather than duplicating them in parameter forms.
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.focusNode,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Slider(
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    label: label,
    onChanged: onChanged,
    focusNode: focusNode,
  );
}
