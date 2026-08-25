import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_section.dart';
import '../../../widgets/app_setting_row.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/settings_widgets.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    
    // No title: the pane header and the mobile detail page's app bar both
    // already say 「外观」, and this printed it a third time.
    return AppSection(
      children: [
        ThemeSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 32),
        ThemeColorSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 32),
        FontSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 32),
        LanguageSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 24),
        AppSettingRow(
          title: l10n.reduceVisualEffects,
          description: l10n.reduceVisualEffectsDesc,
          trailing: AppSwitch(
            value: appState.reduceVisualEffects,
            onChanged: (v) => appState.setReduceVisualEffects(v),
          ),
        ),
      ],
    );
  }
}
