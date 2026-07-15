import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../l10n/app_localizations.dart';
import '../services/font_service.dart';
import '../state/app_state.dart';
import 'app_segmented_control.dart';

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
            child: AppSegmentedControl<ThemeMode>(
              segments: [
                AppSegment(value: ThemeMode.system, label: l10n.themeAuto, icon: Icons.brightness_auto),
                AppSegment(value: ThemeMode.light, label: l10n.themeLight, icon: Icons.light_mode),
                AppSegment(value: ThemeMode.dark, label: l10n.themeDark, icon: Icons.dark_mode),
              ],
              value: appState.themeMode,
              onChanged: appState.setThemeMode,
              expand: true,
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

class FontSelector extends StatelessWidget {
  final AppState appState;
  final AppLocalizations l10n;

  const FontSelector({
    super.key,
    required this.appState,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.font,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
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
                mainAxisExtent: 56,
              ),
              itemCount: AppConstants.fontChoices.length,
              itemBuilder: (context, index) {
                final choice = AppConstants.fontChoices[index];
                final isSystem = choice.key == AppConstants.systemFontKey;
                final label = isSystem ? l10n.fontSystem : choice.label;
                final isSelected = appState.fontFamily == choice.key;

                return _LanguageCard(
                  label: label,
                  icon: isSystem ? Icons.desktop_windows : Icons.font_download,
                  isSelected: isSelected,
                  // Preview each option in its own family (the system option
                  // previews in the resolved OS font).
                  fontFamily:
                      isSystem ? FontService.systemFontFamily : choice.key,
                  onTap: () => _selectFont(context, choice.key),
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// Applies [key], downloading the font first (with a confirmation prompt) if
  /// it is an on-demand family that is not yet cached.
  Future<void> _selectFont(BuildContext context, String key) async {
    if (!FontService.isDownloadable(key)) {
      await appState.setFontFamily(key);
      return;
    }

    if (await FontService.instance.isDownloaded(key)) {
      await FontService.instance.load(key);
      await appState.setFontFamily(key);
      return;
    }

    if (!context.mounted) return;
    final font = FontService.meta(key)!;
    final sizeMB = (font.totalBytes / 1048576).toStringAsFixed(1);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.fontDownloadTitle),
        content: Text('${font.displayName}  ·  ~$sizeMB MB\n\n${l10n.fontDownloadPrompt}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.fontDownloadAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FontDownloadDialog(fontKey: key, l10n: l10n),
    );
    if (ok == true && context.mounted) {
      await appState.setFontFamily(key);
    } else if (ok == false && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fontDownloadFailed)),
      );
    }
  }
}

/// Modal shown while an on-demand font downloads. Kicks off the fetch in
/// [initState] and pops `true` on success / `false` on failure.
class _FontDownloadDialog extends StatefulWidget {
  final String fontKey;
  final AppLocalizations l10n;

  const _FontDownloadDialog({required this.fontKey, required this.l10n});

  @override
  State<_FontDownloadDialog> createState() => _FontDownloadDialogState();
}

class _FontDownloadDialogState extends State<_FontDownloadDialog> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await FontService.instance.download(
        widget.fontKey,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await FontService.instance.load(widget.fontKey);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.l10n.fontDownloading),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress == 0 ? null : _progress),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  // When set, the label renders in this family so font options preview
  // themselves. Null falls back to the ambient theme font.
  final String? fontFamily;

  const _LanguageCard({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.fontFamily,
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
                  fontFamily: fontFamily,
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