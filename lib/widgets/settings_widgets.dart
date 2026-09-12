import 'package:flutter/material.dart';

import '../core/app_semantic_colors.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../services/font_service.dart';
import '../state/app_state.dart';
import 'app_button.dart';
import 'app_dialog.dart';
import 'app_section_label.dart';
import 'theme_accent_picker.dart';

/// The caption every appearance block opens with — `E1`'s 11/500 tracked
/// label in the deep accent — and the gap under it (`1a` 10, `1e` 8).
class _BlockCaption extends StatelessWidget {
  const _BlockCaption(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: Responsive.isMobile(context) ? 8 : AppSpace.s10),
      child: AppSectionLabel(label, padding: EdgeInsets.zero),
    );
  }
}

/// Light / dark / follow the system — `E1 · 1a / 1e`: three equal tiles, 40
/// tall (44 on a phone), each its own bordered choice rather than a segment
/// in a track, because the three are the page's first and largest decision.
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
    final bool phone = Responsive.isMobile(context);
    final modes = [
      (ThemeMode.system, l10n.themeAuto, Icons.brightness_auto_outlined),
      (ThemeMode.light, l10n.themeLight, Icons.light_mode_outlined),
      (ThemeMode.dark, l10n.themeDark, Icons.dark_mode_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockCaption(l10n.themeMode),
        Row(
          children: [
            for (final (int i, (ThemeMode mode, String label, IconData icon)) in modes.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpace.s6),
              Expanded(
                child: _ChoiceTile(
                  height: phone ? AppSize.touch : AppSize.large,
                  selected: appState.themeMode == mode,
                  onTap: () => appState.setThemeMode(mode),
                  child: _TileLabel(icon: icon, label: label, selected: appState.themeMode == mode, centered: true),
                ),
              ),
            ],
          ],
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
        _BlockCaption(l10n.themeColor),
        ThemeAccentPicker(
          selected: appState.themeAccent,
          onSelect: appState.setThemeAccent,
          customSeed: appState.customThemeSeed,
          onCustomSeed: appState.setCustomThemeAccent,
        ),
      ],
    );
  }
}

/// Columns for a grid of 56px option cards in [width]: three where a card
/// can be 170 wide, two down to 140, one below.
int _optionColumns(double width) {
  const double gap = 8;
  return ((width + gap) / (170 + gap)).floor().clamp(width >= 2 * 140 + gap ? 2 : 1, 3);
}

Widget _optionGrid({required int itemCount, required IndexedWidgetBuilder itemBuilder}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final int columns = _optionColumns(constraints.maxWidth);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(2), // room for the selection ring
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: 56,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    },
  );
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
    // Language names are written in their own language, never translated.
    final languages = [
      (null, l10n.themeAuto),
      ('en', 'English'),
      ('zh', '简体中文'),
      ('zh_Hant', '繁體中文'),
      ('ja', '日本語'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockCaption(l10n.language),
        _optionGrid(
          itemCount: languages.length,
          itemBuilder: (context, index) {
            final lang = languages[index];
            final isSelected =
                (lang.$1 == null && appState.locale == null) ||
                    (lang.$1 != null &&
                        appState.locale?.languageCode == (lang.$1!.contains('_') ? lang.$1!.split('_')[0] : lang.$1) &&
                        (appState.locale?.scriptCode == (lang.$1!.contains('_') ? lang.$1!.split('_')[1] : null)));

            return _OptionCard(
              label: lang.$2,
              note: lang.$1 == null ? l10n.languageFollowSystem : null,
              isSelected: isSelected,
              onTap: () {
                final code = lang.$1;
                if (code == null) {
                  appState.setLocale(null);
                } else if (code.contains('_')) {
                  final parts = code.split('_');
                  appState.setLocale(Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]));
                } else {
                  appState.setLocale(Locale(code));
                }
              },
            );
          },
        ),
      ],
    );
  }
}

/// The interface font — `E1 · 1a / 1e`: one card per family, each previewing
/// itself; an on-demand family shows its download size and a download glyph
/// until it is on disk, then the success tick.
class FontSelector extends StatefulWidget {
  final AppState appState;
  final AppLocalizations l10n;

  const FontSelector({
    super.key,
    required this.appState,
    required this.l10n,
  });

  @override
  State<FontSelector> createState() => _FontSelectorState();
}

class _FontSelectorState extends State<FontSelector> {
  /// Which on-demand families are already on disk. Empty until the first
  /// check lands, which only costs the tick a frame.
  Set<String> _downloaded = const {};

  @override
  void initState() {
    super.initState();
    _checkDownloads();
  }

  Future<void> _checkDownloads() async {
    final found = <String>{};
    for (final choice in AppConstants.fontChoices) {
      if (FontService.isDownloadable(choice.key) && await FontService.instance.isDownloaded(choice.key)) {
        found.add(choice.key);
      }
    }
    if (mounted) setState(() => _downloaded = found);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final appState = widget.appState;
    final colorScheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BlockCaption(l10n.font),
        _optionGrid(
          itemCount: AppConstants.fontChoices.length,
          itemBuilder: (context, index) {
            final choice = AppConstants.fontChoices[index];
            final isSystem = choice.key == AppConstants.systemFontKey;
            final label = isSystem ? l10n.fontSystem : choice.label;
            final isSelected = appState.fontFamily == choice.key;
            final meta = FontService.meta(choice.key);
            final bool onDemand = meta != null;
            final bool onDisk = _downloaded.contains(choice.key);

            return _OptionCard(
              label: label,
              isSelected: isSelected,
              // Preview each option in its own family (the system option
              // previews in the resolved OS font).
              fontFamily: isSystem ? FontService.systemFontFamily : choice.key,
              note: isSystem
                  ? l10n.fontFollowSystem
                  : !onDemand
                      ? null
                      : onDisk
                          ? l10n.fontDownloadedOffline
                          : '${AppConstants.formatFileSize(meta.totalBytes)} · ${l10n.fontNotDownloaded}',
              trailing: isSelected
                  ? null
                  : onDemand && !onDisk
                      ? Icon(Icons.download_outlined, size: AppSize.iconMd, color: colorScheme.onAccentTint)
                      : onDemand
                          ? Icon(Icons.check, size: AppSize.iconMd, color: semantic.success)
                          : null,
              onTap: () => _selectFont(context, choice.key),
            );
          },
        ),
      ],
    );
  }

  /// Applies [key], downloading the font first (with a confirmation prompt) if
  /// it is an on-demand family that is not yet cached.
  Future<void> _selectFont(BuildContext context, String key) async {
    final appState = widget.appState;
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
    final ok = await showDialog<bool>(
      context: context,
      animationStyle: appDialogAnimation(context),
      barrierDismissible: false,
      builder: (_) => _FontDownloadDialog(fontKey: key, l10n: widget.l10n),
    );
    if (ok == true && context.mounted) {
      await appState.setFontFamily(key);
      _checkDownloads();
    }
  }
}

enum _DownloadPhase { confirm, downloading, failed }

/// `E1 · 1e` top right: one dialog for the whole download — the prompt with
/// the family and its size, then the progress in place, then (if it fails)
/// the error in place with the same button offering a retry. Pops `true` once
/// the family is downloaded and loaded; Cancel pops nothing.
class _FontDownloadDialog extends StatefulWidget {
  final String fontKey;
  final AppLocalizations l10n;

  const _FontDownloadDialog({required this.fontKey, required this.l10n});

  @override
  State<_FontDownloadDialog> createState() => _FontDownloadDialogState();
}

class _FontDownloadDialogState extends State<_FontDownloadDialog> {
  _DownloadPhase _phase = _DownloadPhase.confirm;
  double _progress = 0;

  Future<void> _run() async {
    setState(() {
      _phase = _DownloadPhase.downloading;
      _progress = 0;
    });
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
      if (mounted) setState(() => _phase = _DownloadPhase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final font = FontService.meta(widget.fontKey)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bool downloading = _phase == _DownloadPhase.downloading;
    final TextStyle? mono = textTheme.labelSmall?.mono.copyWith(
      fontWeight: FontWeight.w400,
      color: colorScheme.onSurfaceVariant,
    );

    return AppDialog(
      icon: Icons.font_download_outlined,
      title: l10n.fontDownloadTitle,
      subtitle: '${font.displayName} · ${AppConstants.formatFileSize(font.totalBytes)}',
      maxWidth: 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.fontDownloadPrompt,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: AppType.proseHeight,
            ),
          ),
          if (_phase != _DownloadPhase.confirm) ...[
            const SizedBox(height: AppSpace.s10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(
                value: downloading && _progress == 0 ? null : _progress,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: AppSpace.s6),
            Row(
              children: [
                Expanded(child: Text(l10n.fontDownloading, style: mono)),
                Text(
                  '${AppConstants.formatFileSize((font.totalBytes * _progress).round())}'
                  ' / ${AppConstants.formatFileSize(font.totalBytes)}',
                  style: mono,
                ),
              ],
            ),
          ],
          if (_phase == _DownloadPhase.failed) ...[
            const SizedBox(height: AppSpace.s10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.error_outline, size: AppSize.iconSm, color: colorScheme.error),
                  ),
                  const SizedBox(width: AppSpace.s6),
                  Expanded(
                    child: Text(
                      l10n.fontDownloadFailed,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        height: AppType.proseHeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          // The download cannot be interrupted; closing only stops waiting
          // for it, and a family that finishes later is simply on disk.
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: downloading ? l10n.fontDownloading : l10n.fontDownloadAction,
          onPressed: downloading ? null : _run,
        ),
      ],
    );
  }
}

/// A bordered choice at r10 on the column colour. Selected: the accent wash
/// (composited, so the ring behind cannot show through), a 1px accent edge
/// and a 2px accent ring outside (`E1` 「选中的主题色卡 / 字体卡 / 语言卡」).
class _ChoiceTile extends StatefulWidget {
  const _ChoiceTile({
    required this.selected,
    required this.onTap,
    required this.child,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  State<_ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<_ChoiceTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool selected = widget.selected;

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (v) => setState(() => _hovered = v),
        onFocusChange: (v) => setState(() => _focused = v),
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.hover),
          curve: AppMotion.quick,
          height: widget.height,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(colorScheme.accentTint, colorScheme.surfaceContainerLow)
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: selected || _focused
                  ? colorScheme.primary
                  : _hovered
                      ? colorScheme.accentRing
                      : colorScheme.outlineVariant,
            ),
            boxShadow: [
              if (_focused) BoxShadow(color: colorScheme.accentRing, spreadRadius: selected ? 5 : 3),
              if (selected) BoxShadow(color: colorScheme.primary, spreadRadius: 2),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// An icon and a label in a [_ChoiceTile], in the deep accent when selected.
class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.icon,
    required this.label,
    required this.selected,
    this.centered = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Color ink = selected ? colorScheme.onAccentTint : colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: centered ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(icon, size: AppSize.iconMd, color: ink),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: ink,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 56px option card: a name (optionally in its own family), an optional
/// note under it, and a glyph at the end — the selection tick, or whatever
/// the caller says about the option.
class _OptionCard extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// When set, the label renders in this family so font options preview
  /// themselves. Null falls back to the ambient theme font.
  final String? fontFamily;

  /// A second, quieter line — a download size, "follows the system".
  final String? note;

  /// Shown when not selected; a selected card always carries the tick.
  final Widget? trailing;

  const _OptionCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.fontFamily,
    this.note,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return _ChoiceTile(
      selected: isSelected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontFamily: fontFamily,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? colorScheme.onAccentTint : colorScheme.onSurface,
                  ),
                ),
                if (note != null)
                  Text(
                    note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (isSelected)
            Icon(Icons.check_circle, size: AppSize.iconMd, color: colorScheme.primary)
          else
            ?trailing,
        ],
      ),
    );
  }
}
