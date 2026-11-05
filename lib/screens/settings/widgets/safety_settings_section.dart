import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../core/safety_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_dialog.dart';
import 'settings_layout.dart';

/// Gemini safety thresholds in Application settings. Editing requires a
/// session-local warning acknowledgement; reopening the page locks editing. Uses
/// [AppState.safetyThresholds].
class SafetySettingsSection extends StatefulWidget {
  const SafetySettingsSection({super.key});

  @override
  State<SafetySettingsSection> createState() => _SafetySettingsSectionState();
}

class _SafetySettingsSectionState extends State<SafetySettingsSection> {
  bool _unlocked = false;

  Future<void> _unlock() async {
    final l10n = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      animationStyle: appDialogAnimation(context),
      builder: (context) => AppDialog(
        title: l10n.safetyUnlockTitle,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
        scrollable: true,
        content: Text(l10n.safetyUnlockWarning),
        actionsOverride: Wrap(
          spacing: AppSpace.s10,
          runSpacing: AppSpace.s10,
          children: [
            AppButton(
              label: l10n.cancel,
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context, false),
            ),
            AppButton(
              label: l10n.safetyUnlockConfirm,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (mounted && accepted == true) setState(() => _unlocked = true);
  }

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
    final thresholds = SafetySettings.normalize(
      context.select<AppState, Map<String, String>>((s) => s.safetyThresholds),
    );

    return SettingsBlock(
      caption: l10n.safetySettings,
      child: SettingsGroup(
        ruled: false,
        children: [
          Text(
            SafetySettings.restricted ? l10n.safetySettingsStoreDesc : l10n.safetySettingsDesc,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          if (!_unlocked)
            AppButton(
              label: l10n.safetyUnlockTitle,
              icon: Icons.lock_outline,
              variant: AppButtonVariant.secondary,
              onPressed: _unlock,
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
                onChanged: !_unlocked
                    ? null
                    : (v) {
                        Provider.of<AppState>(
                          context,
                          listen: false,
                        ).setSafetyThreshold(category, SafetySettings.thresholds[v.round()]);
                      },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
