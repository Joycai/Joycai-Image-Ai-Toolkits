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
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeAuto), icon: const Icon(Icons.brightness_auto, size: 18)),
                ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight), icon: const Icon(Icons.light_mode, size: 18)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark), icon: const Icon(Icons.dark_mode, size: 18)),
              ],
              selected: {appState.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (Set<ThemeMode> newSelection) {
                appState.setThemeMode(newSelection.first);
              },
            ),
          ),
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
    // Define the supported languages
    final languages = [
      (null, l10n.themeAuto, Icons.auto_awesome),
      ('en', 'English', Icons.language),
      ('zh', '简体中文', Icons.translate),
      ('zh_Hant', '繁體中文', Icons.translate),
      ('ja', '日本語', Icons.translate),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.language,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Determine column count based on width
            int crossAxisCount = constraints.maxWidth > 600
                ? 3
                : (constraints.maxWidth > 350 ? 2 : 1);

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 56, // Fixed height for items
              ),
              itemCount: languages.length,
              itemBuilder: (context, index) {
                final lang = languages[index];
                final isSelected =
                    (lang.$1 == null && appState.locale == null) ||
                        (lang.$1 != null &&
                            appState.locale?.languageCode == (lang.$1!.contains('_') ? lang.$1!.split('_')[0] : lang.$1) &&
                            (appState.locale?.scriptCode == (lang.$1!.contains('_') ? lang.$1!.split('_')[1] : null)));

                return _LanguageCard(
                  label: lang.$2,
                  icon: lang.$3,
                  isSelected: isSelected,
                  onTap: () {
                    final code = lang.$1;
                    if (code == null) {
                      appState.setLocale(null);
                    } else if (code.contains('_')) {
                      final parts = code.split('_');
                      appState.setLocale(Locale.fromSubtags(
                          languageCode: parts[0], scriptCode: parts[1]));
                    } else {
                      appState.setLocale(Locale(code));
                    }
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withAlpha(100),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                size: 16,
                color: colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}