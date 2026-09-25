part of '../theme_accent_picker.dart';

/// `1a` — three cards to a row in the 720px settings column, two on a
/// narrower one. The count comes from the width the grid is given, not from a
/// breakpoint: the same picker sits in the tablet card and the desktop one.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.picker});

  final ThemeAccentPicker picker;

  static const double _gap = AppSpace.s10;

  /// Below this a card's halves cannot hold their hex values side by side.
  static const double _minCardWidth = 170;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 3 * ThemeAccentPreviewCard.width + 2 * _gap;
            final int columns = ((width + _gap) / (_minCardWidth + _gap)).floor().clamp(2, 3);
            final double cardWidth = ((width - _gap * (columns - 1)) / columns).floorToDouble();

            return Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [
                for (final MapEntry<String, ThemeAccent> preset
                    in AppConstants.presetThemes.entries)
                  ThemeAccentPreviewCard(
                    accent: preset.value,
                    name: preset.key,
                    selected: picker.selected == preset.value,
                    onTap: () => picker.onSelect(preset.key),
                    cardWidth: cardWidth,
                  ),
                if (picker.onCustomSeed != null)
                  _CustomAccentCard(
                    width: cardWidth,
                    active: picker._customActive,
                    accent: picker.selected,
                    onTap: () => picker._openCustom(context),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpace.s10),
        _Hint(l10n.themeColorHintCards, maxWidth: 640),
      ],
    );
  }
}

/// The shell every theme-colour card shares — `1a`: an 8px column-coloured
/// frame at r10 around a 96px preview, the name under it.
///
/// Selected: the accent wash (composited onto the column colour, so the ring
/// drawn behind it cannot show through), a 1px accent edge and a 2px accent
/// ring outside. Hover borrows only the 32% edge. Keyboard focus draws a 2px
/// gap of panel colour and a 2px accent ring — or, on a selected card, a 3px
/// 32% ring outside the selection's.
class _CardShell extends StatefulWidget {
  const _CardShell({
    required this.width,
    required this.selected,
    required this.onTap,
    required this.preview,
    required this.name,
  });

  final double width;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;
  final String name;

  @override
  State<_CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<_CardShell> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool selected = widget.selected;

    final List<BoxShadow> rings = [
      if (_focused && selected) BoxShadow(color: colorScheme.accentRing, spreadRadius: 5),
      if (_focused && !selected) BoxShadow(color: colorScheme.primary, spreadRadius: 4),
      if (_focused && !selected) BoxShadow(color: colorScheme.surface, spreadRadius: 2),
      if (selected) BoxShadow(color: colorScheme.primary, spreadRadius: 2),
    ];

    return InkWell(
      onTap: widget.onTap,
      onHover: (v) => setState(() => _hovered = v),
      onFocusChange: (v) => setState(() => _focused = v),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.hover),
        curve: AppMotion.quick,
        width: widget.width,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(colorScheme.accentTint, colorScheme.surfaceContainerLow)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : _hovered
                ? colorScheme.accentRing
                : colorScheme.outlineVariant,
          ),
          boxShadow: rings,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(height: ThemeAccentPreviewCard.previewHeight, child: widget.preview),
            ),
            const SizedBox(height: AppSpace.s6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? colorScheme.onAccentTint : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (selected) Icon(Icons.check, size: AppSize.iconSm, color: colorScheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One preset as a picture of itself in both modes — design `1a`.
///
/// The left half is the *light* panel with the light scheme's accent on it,
/// the right half the *dark* panel with the dark scheme's — always, whatever
/// mode the app is in. Only the shell follows the current theme.
class ThemeAccentPreviewCard extends StatelessWidget {
  const ThemeAccentPreviewCard({
    super.key,
    required this.accent,
    required this.name,
    required this.selected,
    required this.onTap,
    this.cardWidth,
  });

  final ThemeAccent accent;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  /// The card's width; null takes [width]. The picker's grid passes the
  /// column width it computed.
  final double? cardWidth;

  /// The width a card takes when nothing sets one.
  static const double width = 172;

  static const double previewHeight = 96;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ColorScheme light = buildAppColorScheme(accent: accent, brightness: Brightness.light);
    final ColorScheme dark = buildAppColorScheme(accent: accent, brightness: Brightness.dark);

    return _CardShell(
      width: cardWidth ?? width,
      selected: selected,
      onTap: onTap,
      name: name,
      preview: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PreviewHalf(
              scheme: light,
              // In light mode the light half is nearly the colour of the card
              // around it, so it takes an inset hairline to keep its edge.
              hairline: colorScheme.brightness == Brightness.light,
            ),
          ),
          Expanded(child: _PreviewHalf(scheme: dark, hairline: false)),
        ],
      ),
    );
  }
}

/// `1a`'s last card: the hue ring and its eyedropper, or — once a custom
/// colour is in use — that colour's two halves, like any preset.
class _CustomAccentCard extends StatelessWidget {
  const _CustomAccentCard({
    required this.width,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final double width;
  final bool active;
  final ThemeAccent accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Widget preview;
    if (active) {
      preview = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PreviewHalf(
              scheme: buildAppColorScheme(accent: accent, brightness: Brightness.light),
              hairline: colorScheme.brightness == Brightness.light,
            ),
          ),
          Expanded(
            child: _PreviewHalf(
              scheme: buildAppColorScheme(accent: accent, brightness: Brightness.dark),
              hairline: false,
            ),
          ),
        ],
      );
    } else {
      preview = DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: _hueStops)),
        child: const Center(child: Icon(Icons.colorize, size: 24, color: Colors.white)),
      );
    }

    return _CardShell(
      width: width,
      selected: active,
      onTap: onTap,
      name: AppLocalizations.of(context)!.themeColorCustom,
      preview: preview,
    );
  }
}

/// One mode's half of the preview: a filled button, a switch beside a
/// selected row, and the value — each in the shades that mode really uses.
///
/// Every colour here comes from the *scheme passed in*, not the ambient
/// theme — the half is a picture of another theme, which is the point.
class _PreviewHalf extends StatelessWidget {
  const _PreviewHalf({required this.scheme, required this.hairline});

  final ColorScheme scheme;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final pill = BorderRadius.circular(AppRadius.pill);

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.all(8),
      foregroundDecoration: hairline
          ? BoxDecoration(border: Border.all(color: scheme.outlineVariant))
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 主色实底 — the CTA, with its label as a bar of `onPrimary`.
          Container(
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(color: scheme.onPrimary, borderRadius: pill),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              // 主色纯色 — a switch in its on state.
              Container(
                width: 24,
                height: 14,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: scheme.primary, borderRadius: pill),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: scheme.onPrimary, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 4),
              // 主色 12% + 主色深 — a selected row.
              Expanded(
                child: Container(
                  height: 14,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: scheme.accentTint,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: scheme.onAccentTint, shape: BoxShape.circle),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _hex(scheme.primary),
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
              fontWeight: FontWeight.w400,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
