import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../ui/app_field_size.dart';
import '../../ui/app_switch.dart';
import 'model_edit_metrics.dart';

/// A single-line input at the form's height, with an optional leading glyph.
class ModelEditTextField extends StatelessWidget {
  const ModelEditTextField({
    super.key,
    required this.controller,
    this.onChanged,
    this.icon,
    this.hint,
    this.mono = false,
    this.error = false,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
    this.suffixText,
    this.suffix,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final IconData? icon;
  final String? hint;
  final FocusNode? focusNode;

  /// A unit after the value, in the secondary ink (「tokens」).
  final String? suffixText;

  /// A control at the field's end, on the field's own height — the context
  /// window's preset menu. Laid out unconstrained so it can draw its own
  /// divider from edge to edge.
  final Widget? suffix;

  /// Identifiers and numbers the wire sees verbatim.
  final bool mono;

  /// `D1c` 「校验失败 = err 描边」.
  final bool error;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);
    final base = theme.textTheme.bodyMedium;
    final style = mono ? base?.mono : base;
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: scheme.error),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: style,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        constraints: BoxConstraints.tightFor(height: metrics.fieldHeight),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpace.s10,
          vertical: pinnedFieldInset(context, style, metrics.fieldHeight),
        ),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: AppSize.iconMd, color: scheme.onSurfaceVariant),
        suffixText: suffixText,
        suffixStyle: style?.copyWith(color: scheme.onSurfaceVariant),
        suffixIcon: suffix,
        suffixIconConstraints: suffix == null ? null : const BoxConstraints(minWidth: 0, minHeight: 0),
        enabledBorder: error ? errorBorder : null,
        focusedBorder: error ? errorBorder : null,
      ),
    );
  }
}

/// One cell of a [ModelEditChoiceGrid].
@immutable
class ModelEditChoice<T> {
  const ModelEditChoice({required this.value, required this.label, this.dotColor});

  final T value;
  final String label;

  /// An identity colour drawn as a 6px dot before the label. It never takes
  /// the accent, selected or not — the kind's hue is the kind's.
  final Color? dotColor;
}

/// Equal cells in one row: the kind picker and the context-window modes.
///
/// Selected is the accent's wash with a `primary` stroke and the deep ink at
/// 600; a dot keeps its identity colour either way.
class ModelEditChoiceGrid<T> extends StatelessWidget {
  const ModelEditChoiceGrid({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final List<ModelEditChoice<T>> choices;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.s6),
          Expanded(
            child: _ChoiceCell<T>(
              choice: choices[i],
              selected: choices[i].value == value,
              onTap: () => onChanged(choices[i].value),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceCell<T> extends StatelessWidget {
  const _ChoiceCell({required this.choice, required this.selected, required this.onTap});

  final ModelEditChoice<T> choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);
    final radius = BorderRadius.circular(AppRadius.control);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.durationOf(context, AppMotion.hover),
            curve: AppMotion.quick,
            height: metrics.gridHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
            decoration: BoxDecoration(
              color: selected ? scheme.accentTint : metrics.fill(scheme),
              borderRadius: radius,
              border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (choice.dotColor != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: choice.dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpace.s6),
                ],
                Flexible(
                  child: Text(
                    choice.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.onAccentTint : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The form's card: the column colour, a hairline, r10.
class ModelEditCard extends StatelessWidget {
  const ModelEditCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.s10)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: ModelEditMetrics.of(context).fill(scheme),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// A switch row inside a [ModelEditCard].
///
/// [description] is drawn under the title; [tooltip] instead keeps a row at
/// its 40px (`1a`'s capability rows carry only the title) without dropping
/// the explanation the row used to print.
class ModelEditToggleRow extends StatelessWidget {
  const ModelEditToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.tooltip,
    this.emphasized = false,
    this.dimmed = false,
  });

  final String title;
  final String? description;
  final String? tooltip;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 600 rather than 500 — a card holding a single setting (`1a` 代理行为).
  final bool emphasized;

  /// Inert because something else overrides it; the value is kept.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = ModelEditMetrics.of(context);

    Widget titleText = Text(
      title,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
      ),
    );
    if (tooltip != null) titleText = Tooltip(message: tooltip!, child: titleText);

    return AnimatedOpacity(
      opacity: dimmed ? AppAlpha.edge : 1,
      duration: AppMotion.durationOf(context, AppMotion.state),
      curve: AppMotion.enter,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: description == null ? metrics.toggleRowHeight : 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleText,
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w400,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpace.s10),
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
