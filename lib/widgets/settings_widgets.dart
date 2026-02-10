import 'package:flutter/material.dart';

import '../core/constants.dart';
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

class ThemeColorSelector extends StatelessWidget {
  final AppState appState;
  final AppLocalizations l10n;

  const ThemeColorSelector({
    super.key,
    required this.appState,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Theme Color", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: AppConstants.presetThemes.entries.map((entry) {
            final isSelected = appState.themeSeedColor.toARGB32() == entry.value.toARGB32();
            return Tooltip(
              message: entry.key,
              child: InkWell(
                onTap: () => appState.setThemeSeedColor(entry.value),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: entry.value.withAlpha(100),
                          blurRadius: 8,
                          spreadRadius: 2,
                        )
                    ],
                  ),
                  child: isSelected 
                    ? Icon(Icons.check, size: 20, color: ThemeData.estimateBrightnessForColor(entry.value) == Brightness.dark ? Colors.white : Colors.black) 
                    : null,
                ),
              ),
            );
          }).toList(),
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
          segments: [
            ButtonSegment(value: null, label: Text(l10n.themeAuto)),
            const ButtonSegment(value: 'en', label: Text('English')),
            const ButtonSegment(value: 'zh', label: Text('中文')),
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
