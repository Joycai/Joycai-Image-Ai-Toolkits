part of '../theme_accent_picker.dart';

/// `1e` — 44px dots, four to a row, with Custom… on its own row under a
/// hairline, and the hint.
class _DotGrid extends StatelessWidget {
  const _DotGrid({required this.picker});

  final ThemeAccentPicker picker;

  /// `1e`: 10 between dots.
  static const double _gap = AppSpace.s10;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final double spacing = _gap - 2 * DualToneSwatch.hitInset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // The rings paint outside the hit boxes; this keeps the top row's
          // clear of whatever sits above.
          padding: const EdgeInsets.only(top: 4),
          child: SizedBox(
            // Pinned to four columns: eight dots in two rows of four is the
            // shape `1e` settled on, and a wider page would otherwise run six
            // and two.
            width: 4 * DualToneSwatch.hitSize + 3 * spacing,
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final MapEntry<String, ThemeAccent> preset in AppConstants.presetThemes.entries)
                  DualToneSwatch(
                    accent: preset.value,
                    name: preset.key,
                    pairLabel: l10n.themeColorPair(
                      _hex(buildAppColorScheme(accent: preset.value, brightness: Brightness.light).primary),
                      _hex(buildAppColorScheme(accent: preset.value, brightness: Brightness.dark).primary),
                    ),
                    selected: picker.selected == preset.value,
                    onTap: () => picker.onSelect(preset.key),
                  ),
              ],
            ),
          ),
        ),
        if (picker.onCustomSeed != null)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: InkWell(
              onTap: () => picker._openCustom(context),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    _HueDot(selected: picker._customActive),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.themeColorCustom,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: picker._customActive ? FontWeight.w600 : FontWeight.w400,
                              color: picker._customActive ? colorScheme.onAccentTint : colorScheme.onSurface,
                            ),
                      ),
                    ),
                    if (picker.customSeed != null && picker._customActive)
                      Text(
                        _hex(picker.customSeed!),
                        style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _Hint(l10n.themeColorHintDots, maxWidth: 560),
      ],
    );
  }
}

/// The phone form of Custom…: a 44px dot of the hue ring with the eyedropper
/// on it, ringed like a selected swatch while a custom colour is in use.
class _HueDot extends StatelessWidget {
  const _HueDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: DualToneSwatch.dotSize,
      height: DualToneSwatch.dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: _hueStops),
        boxShadow: selected
            ? [
                BoxShadow(color: colorScheme.primary, spreadRadius: 4),
                BoxShadow(color: colorScheme.surface, spreadRadius: 2),
              ]
            : null,
      ),
      child: const Icon(Icons.colorize, size: AppSize.iconLg, color: Colors.white),
    );
  }
}
