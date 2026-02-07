import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';

class ThemeSelector extends StatelessWidget {
  final AppState appState;
  final AppLocalizations l10n;

  const ThemeSelector({
    super.key,
    required this.appState,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.appearance, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeAuto), icon: const Icon(Icons.brightness_auto)),
            ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight), icon: const Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark), icon: const Icon(Icons.dark_mode)),
          ],
          selected: {appState.themeMode},
          onSelectionChanged: (Set<ThemeMode> newSelection) {
            appState.setThemeMode(newSelection.first);
          },
        ),
      ],
    );
  }
}

class LanguageSelector extends StatelessWidget {
  final AppState appState;
  final AppLocalizations l10n;

  const LanguageSelector({
    super.key,
    required this.appState,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.language, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 8),
        SegmentedButton<String?>(
          segments: const [
            ButtonSegment(value: null, label: Text('Default')),
            ButtonSegment(value: 'en', label: Text('English')),
            ButtonSegment(value: 'zh', label: Text('中文')),
          ],
          selected: {appState.locale?.languageCode},
          onSelectionChanged: (Set<String?> newSelection) {
            final code = newSelection.first;
            appState.setLocale(code == null ? null : Locale(code));
          },
        ),
      ],
    );
  }
}
