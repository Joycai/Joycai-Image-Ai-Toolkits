import 'package:flutter/material.dart';

import '../../../core/design_tokens.dart';

/// Geometry that differs between the desktop dialog and the phone page.
///
/// D1c draws the same form twice: fields at 32 in the dialog and 44 on the
/// phone, the choice grids at 32 / 40, switch rows at 40 / 48. Carried down
/// the tree rather than passed through every builder so a field cannot be
/// built at the other form's height by mistake.
@immutable
class ModelEditMetrics {
  const ModelEditMetrics._({
    required this.phone,
    required this.onColumnGround,
    required this.fieldHeight,
    required this.gridHeight,
    required this.toggleRowHeight,
    required this.inlineActionHeight,
  });

  /// The dialog (`1a`): a panel ground, fields and cards on the column colour.
  static const desktop = ModelEditMetrics._(
    phone: false,
    onColumnGround: false,
    fieldHeight: AppSize.control,
    gridHeight: AppSize.control,
    toggleRowHeight: AppSize.large,
    inlineActionHeight: AppSize.compact,
  );

  /// The phone page (`1e`): a column ground, fields and cards on the panel.
  static const phoneForm = ModelEditMetrics._(
    phone: true,
    onColumnGround: true,
    fieldHeight: AppSize.touch,
    gridHeight: AppSize.large,
    // `1e` 「能力卡行 48」.
    toggleRowHeight: AppSize.touch + AppSpace.s4,
    inlineActionHeight: AppSize.control,
  );

  /// A dialog on a phone (the add-model dialog): touch heights on a panel.
  static const phoneDialog = ModelEditMetrics._(
    phone: true,
    onColumnGround: false,
    fieldHeight: AppSize.touch,
    gridHeight: AppSize.large,
    toggleRowHeight: AppSize.touch + AppSpace.s4,
    inlineActionHeight: AppSize.control,
  );

  /// Touch geometry, and the phone's own affordances (a bottom sheet in
  /// place of a menu).
  final bool phone;

  /// Whether the form sits on the column colour rather than on a panel.
  final bool onColumnGround;
  final double fieldHeight;
  final double gridHeight;
  final double toggleRowHeight;

  /// 「改回自动」: compact under a dialog field, a touch step taller on phone.
  final double inlineActionHeight;

  /// What a field and a card fill with: a step off whatever they sit on.
  Color fill(ColorScheme scheme) => onColumnGround ? scheme.surface : scheme.surfaceContainerLow;

  static ModelEditMetrics of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MetricsScope>()?.metrics ?? desktop;
}

class _MetricsScope extends InheritedWidget {
  const _MetricsScope({required this.metrics, required super.child});

  final ModelEditMetrics metrics;

  @override
  bool updateShouldNotify(_MetricsScope oldWidget) => metrics != oldWidget.metrics;
}

/// Sets the editor's field skin and [ModelEditMetrics] for everything below.
///
/// The fill is the form's own (`D1c`: 「字段填充与卡容器 = col」), which is why
/// this is not `FilledFieldScope`: that one fills with the lowest surface for
/// the older D2 forms.
class ModelEditFieldScope extends StatelessWidget {
  const ModelEditFieldScope({super.key, required this.metrics, required this.child});

  final ModelEditMetrics metrics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: metrics.fill(theme.colorScheme),
          prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 0),
        ),
      ),
      child: _MetricsScope(metrics: metrics, child: child),
    );
  }
}
