import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/spec_rate.dart';
import '../../../../services/llm/generation/generation_param.dart';
import '../../../../services/llm/generation/generation_schema.dart';
import '../../../../services/llm/generation/generation_value.dart';
import '../../../../services/llm/param_spec.dart';
import 'generation_param_texts.dart';
import 'param_editor_registry.dart';
import 'param_presentation.dart';

/// The current workbench geometry shared by image and video. It inherits
/// fonts, themes and reduced effects from the existing control primitives.
class GenerationParamPanel extends StatelessWidget {
  const GenerationParamPanel({
    super.key,
    required this.specs,
    required this.valueOf,
    required this.onChanged,
    this.video = false,
    this.modelName = '',
    this.storedValueOf,
    this.rates,
    this.schema,
    this.registry = ParamEditorRegistry.standard,
    this.presentation = const {},
  });

  final List<ParamSpec> specs;
  final String Function(ParamSpec) valueOf;
  final void Function(String key, String value) onChanged;
  final bool video;
  final String modelName;
  final String? Function(String key)? storedValueOf;
  final List<SpecRate>? rates;
  final GenerationSchema? schema;
  final ParamEditorRegistry registry;
  final Map<String, ParamPresentation> presentation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final draft = {for (final spec in specs) spec.key: GenerationParam(spec).decode(valueOf(spec))};
    final operation = schema?.operation(draft, const []);
    final cells = <(Widget, bool)>[];
    for (final diagnostic in schema?.configurationDiagnostics ?? <GenerationDiagnostic>[]) {
      cells.add((
        Text(
          GenerationParamTexts.diagnostic(l10n, diagnostic),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
        true,
      ));
    }
    if (operation == GenerationOperation.layers) {
      cells.add((
        Text(l10n.generationLayersRatioInactive, style: Theme.of(context).textTheme.labelSmall),
        true,
      ));
    }
    if (operation == GenerationOperation.transparent) {
      cells.add((
        Text(l10n.generationTransparentSource, style: Theme.of(context).textTheme.labelSmall),
        true,
      ));
    }
    for (final spec in specs) {
      final fieldState = operation == null
          ? GenerationFieldState.active
          : schema!.fieldState(spec.key, operation);
      if (fieldState == GenerationFieldState.inactive) continue;
      final param = GenerationParam(spec);
      final appearance = presentation[spec.key] ?? const ParamPresentation();
      final value = fieldState == GenerationFieldState.fixed
          ? const GenerationValue(GenerationValueKind.choice, 'png')
          : draft[spec.key]!;
      final label = GenerationParamTexts.label(l10n, spec.labelKey, video: video);
      final control = registry.build(
        context,
        ParamEditorData(
          param: param,
          value: value,
          optionLabel: (v) => GenerationParamTexts.option(
            l10n,
            spec.key,
            v,
            hasExplicitAuto: spec.options.any((o) => o.value == 'auto'),
          ),
          onChanged: (v) => onChanged(spec.key, param.encode(v)),
          modelName: modelName,
          storedValue: storedValueOf?.call(spec.key),
          rates: rates,
          editor: appearance.editorFor(spec),
        ),
      );
      final cell = KeyedSubtree(
        key: ValueKey(spec.key),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpace.s4),
              if (fieldState == GenerationFieldState.fixed)
                Semantics(
                  enabled: false,
                  child: ExcludeFocus(child: IgnorePointer(child: control)),
                )
              else
                control,
              if (fieldState == GenerationFieldState.fixed) ...[
                const SizedBox(height: AppSpace.s4),
                Text(l10n.generationFixedPng, style: Theme.of(context).textTheme.labelSmall),
              ],
              if (storedValueOf?.call(spec.key) case final stored?)
                if (!spec.isValid(stored)) ...[
                  const SizedBox(height: AppSpace.s4),
                  Text(l10n.generationStoredReset, style: Theme.of(context).textTheme.labelSmall),
                ],
            ],
          ),
        ),
      );
      cells.add((cell, appearance.fullRowFor(spec)));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = <Widget>[];
        Widget? pending;
        for (final (cell, full) in cells) {
          if (full || constraints.maxWidth < 240) {
            if (pending != null) {
              rows.add(pending);
              pending = null;
            }
            rows.add(cell);
          } else if (pending == null) {
            pending = cell;
          } else {
            rows.add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: pending),
                  const SizedBox(width: AppSpace.s6),
                  Expanded(child: cell),
                ],
              ),
            );
            pending = null;
          }
        }
        if (pending != null) rows.add(pending);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, row) in rows.indexed) ...[
              if (index > 0) const SizedBox(height: AppSpace.s6),
              row,
            ],
          ],
        );
      },
    );
  }
}
