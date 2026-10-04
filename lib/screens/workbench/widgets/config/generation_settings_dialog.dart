import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../state/app_state.dart';
import '../../../../widgets/ui/app_button.dart';
import '../../../../widgets/ui/app_dialog.dart';
import '../../../../widgets/ui/app_section_label.dart';
import '../../../../widgets/ui/app_setting_row.dart';
import '../../../../widgets/ui/app_text_field.dart';
import 'safety_settings_section.dart';

/// Shared output preferences and execution controls for image/video generation.
Future<void> showGenerationSettingsDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final prefixController = TextEditingController(text: context.read<AppState>().imagePrefix);
  return AppDialog.show<void>(
    context,
    title: l10n.generationSettings,
    maxWidth: 480,
    content: Consumer<AppState>(
      builder: (context, state, _) {
        final theme = Theme.of(context);
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.generationSettingsDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              AppSectionLabel(l10n.generationOutputFiles),
              AppToggleRow(
                title: l10n.saveGenerationText,
                description: l10n.saveGenerationTextDesc,
                value: state.saveGenerationText,
                onChanged: state.setSaveGenerationText,
              ),
              const SizedBox(height: AppSpace.s10),
              Text(l10n.filenamePrefix, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpace.s6),
              AppTextField(
                controller: prefixController,
                hint: l10n.prefixHint,
                onChanged: state.setImagePrefix,
              ),
              AppSectionLabel(l10n.generationExecution),
              LayoutBuilder(
                builder: (context, constraints) {
                  final concurrency = _ExecutionControl(
                    label: l10n.concurrencyLimit(state.concurrencyLimit),
                    value: state.concurrencyLimit,
                    min: 1,
                    max: 8,
                    onChanged: state.setConcurrency,
                  );
                  final retries = _ExecutionControl(
                    label: l10n.retryCount(state.retryCount),
                    value: state.retryCount,
                    min: 0,
                    max: 5,
                    onChanged: state.setRetryCount,
                  );
                  if (constraints.maxWidth >= 400) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: concurrency),
                        const SizedBox(width: AppSpace.s16),
                        Expanded(child: retries),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      concurrency,
                      const SizedBox(height: AppSpace.s6),
                      retries,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpace.s6),
              const Divider(height: AppSpace.s10),
              const SafetySettingsSection(),
            ],
          ),
        );
      },
    ),
    actions: [
      AppButton(
        label: l10n.close,
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  ).then((_) => prefixController.dispose());
}

class _ExecutionControl extends StatelessWidget {
  const _ExecutionControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodyMedium),
      Slider(
        value: value.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        label: '$value',
        onChanged: (v) => onChanged(v.toInt()),
      ),
    ],
  );
}
