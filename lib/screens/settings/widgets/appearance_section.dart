import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_setting_row.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/settings_widgets.dart';
import 'settings_layout.dart';

/// `E1 · 1a / 1e`: mode, theme colour, font, language, and reduce visual
/// effects with the one line on what it changes.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);

    // No title: the pane header and the phone detail page's header both
    // already name the category.
    return SettingsSections(
      children: [
        ThemeSelector(appState: appState, l10n: l10n),
        ThemeColorSelector(appState: appState, l10n: l10n),
        FontSelector(appState: appState, l10n: l10n),
        LanguageSelector(appState: appState, l10n: l10n),
        SettingsBlock(
          caption: l10n.visualEffects,
          child: AppSettingRow(
            title: l10n.reduceVisualEffects,
            description: l10n.reduceVisualEffectsDesc,
            trailing: AppSwitch(
              value: appState.reduceVisualEffects,
              onChanged: (v) => appState.setReduceVisualEffects(v),
            ),
          ),
        ),
      ],
    );
  }
}
