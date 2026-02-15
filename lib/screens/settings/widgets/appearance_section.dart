import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/app_section.dart';
import '../../../widgets/settings_widgets.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    
    return AppSection(
      title: l10n.appearance,
      children: [
        ThemeSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 32),
        ThemeColorSelector(appState: appState, l10n: l10n),
        const SizedBox(height: 32),
        LanguageSelector(appState: appState, l10n: l10n),
      ],
    );
  }
}
