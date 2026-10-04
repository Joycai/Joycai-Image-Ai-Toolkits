import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/safety_settings.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../state/app_state.dart';
import '../../../../widgets/ui/app_disclosure_chevron.dart';

/// Per-category Gemini safety-threshold sliders (strict → permissive), shared
/// by the image and video workbench generation-settings dialogs. Reads and writes
/// [AppState.safetyThresholds].
class SafetySettingsSection extends StatefulWidget {
  const SafetySettingsSection({super.key});

  @override
  State<SafetySettingsSection> createState() => _SafetySettingsSectionState();
}

class _SafetySettingsSectionState extends State<SafetySettingsSection> {
  bool _expanded = false;

  String _categoryLabel(AppLocalizations l10n, String category) {
    switch (category) {
      case 'HARM_CATEGORY_HARASSMENT':
        return l10n.safetyCategoryHarassment;
      case 'HARM_CATEGORY_HATE_SPEECH':
        return l10n.safetyCategoryHateSpeech;
      case 'HARM_CATEGORY_SEXUALLY_EXPLICIT':
        return l10n.safetyCategorySexuallyExplicit;
      case 'HARM_CATEGORY_DANGEROUS_CONTENT':
        return l10n.safetyCategoryDangerousContent;
      default:
        return category;
    }
  }

  String _thresholdLabel(AppLocalizations l10n, String threshold) {
    switch (threshold) {
      case 'BLOCK_LOW_AND_ABOVE':
        return l10n.safetyThresholdBlockLowAndAbove;
      case 'BLOCK_MEDIUM_AND_ABOVE':
        return l10n.safetyThresholdBlockMediumAndAbove;
      case 'BLOCK_ONLY_HIGH':
        return l10n.safetyThresholdBlockOnlyHigh;
      case 'BLOCK_NONE':
        return l10n.safetyThresholdBlockNone;
      case 'OFF':
        return l10n.safetyThresholdOff;
      default:
        return threshold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final thresholds = context.select<AppState, Map<String, String>>((s) => s.safetyThresholds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          expanded: _expanded,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSize.touch),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: AppSize.iconSm, color: colorScheme.accentText),
                  const SizedBox(width: AppSpace.s6),
                  Expanded(child: Text(l10n.safetySettings, style: textTheme.bodyMedium)),
                  AppDisclosureChevron(
                    open: _expanded,
                    size: AppSize.iconSm,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: AppSpace.s4),
          Text(
            l10n.safetySettingsDesc,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          for (final category in SafetySettings.categories) ...[
            const SizedBox(height: AppSpace.s10),
            Row(
              children: [
                Expanded(child: Text(_categoryLabel(l10n, category), style: textTheme.bodySmall)),
                Text(
                  _thresholdLabel(l10n, thresholds[category] ?? SafetySettings.defaultThreshold),
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.accentText,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: AppSize.compact,
              child: Slider(
                value: SafetySettings.thresholds
                    .indexOf(thresholds[category] ?? SafetySettings.defaultThreshold)
                    .clamp(0, SafetySettings.thresholds.length - 1)
                    .toDouble(),
                min: 0,
                max: (SafetySettings.thresholds.length - 1).toDouble(),
                divisions: SafetySettings.thresholds.length - 1,
                onChanged: (v) {
                  Provider.of<AppState>(
                    context,
                    listen: false,
                  ).setSafetyThreshold(category, SafetySettings.thresholds[v.round()]);
                },
              ),
            ),
          ],
        ],
      ],
    );
  }
}
