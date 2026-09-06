import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../core/theme_accent.dart';
import '../l10n/app_localizations.dart';
import 'dual_tone_swatch.dart';

/// The theme-colour chooser on the appearance card — design `D1a 20a–20e`.
///
/// Two forms of the same control, picked by width, because the two things a
/// user needs from it do not fit in one shape:
///
/// - **Desktop and tablet: preview cards** (`20b`, the design's recommended
///   form). Each card is a miniature of both modes side by side — a filled
///   button, a switch and a selected row, drawn in the exact shade each mode
///   will use — so the dark half of a pair can be judged *before* it is
///   chosen. That is the one thing a swatch cannot show, and the reason the
///   accent became a pair in the first place.
/// - **Mobile: dual-tone dots** (`20e`). Eight cards would be four rows of
///   scrolling on a phone, and the design's own argument for the dots there
///   is that the section's whole value is comparing all eight at a glance.
///   Four per row, two rows, no horizontal scroll; the pair's values are on
///   the long-press tooltip instead of in the picture.
///
/// Stateless on purpose: it reports the chosen preset's *key* and lets the
/// caller persist it, so it can be photographed by the gallery and tested
/// without an [AppState].
class ThemeAccentPicker extends StatelessWidget {
  const ThemeAccentPicker({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  /// The pair currently in use — compared by value against each preset.
  final ThemeAccent selected;

  /// Called with the [AppConstants.presetThemes] key the user picked.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Responsive.isMobile(context) ? _DotGrid(picker: this) : _CardGrid(picker: this);
  }
}

/// `20b` / `20c` — four 162px cards to a row in the 720px settings column,
/// flowing to fewer on a narrower one.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.picker});

  final ThemeAccentPicker picker;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry<String, ThemeAccent> preset in AppConstants.presetThemes.entries)
              ThemeAccentPreviewCard(
                accent: preset.value,
                name: preset.key,
                selected: picker.selected == preset.value,
                onTap: () => picker.onSelect(preset.key),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _Hint(l10n.themeColorHintCards, maxWidth: 600),
      ],
    );
  }
}

/// `20e` — 36px dots on a 20/16 grid, a disabled "custom" placeholder under a
/// hairline, and the hint.
///
/// The placeholder is drawn because the design draws it: the row is where a
/// custom colour will go, and reserving the slot now means the eight dots do
/// not shift when it arrives. It does nothing yet, and says so at 38%.
class _DotGrid extends StatelessWidget {
  const _DotGrid({required this.picker});

  final ThemeAccentPicker picker;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // The dots' hit boxes are 4px wider than the dots on every side;
          // these gaps land the *dots* on the design's 20/16 grid. The width
          // pins the grid to four columns: eight dots in two rows of four is
          // the shape the design settled on for a phone, and a wider page
          // (the appearance page has no card around it) would otherwise run
          // six and two.
          padding: const EdgeInsets.only(top: 4),
          child: SizedBox(
            width: 4 * DualToneSwatch.hitSize + 3 * (20 - 2 * DualToneSwatch.hitInset),
            child: Wrap(
              spacing: 20 - 2 * DualToneSwatch.hitInset,
              runSpacing: 16 - 2 * DualToneSwatch.hitInset,
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
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Opacity(
            opacity: AppAlpha.disabled,
            child: Row(
              children: [
                SizedBox(
                  width: DualToneSwatch.dotSize,
                  height: DualToneSwatch.dotSize,
                  child: CustomPaint(
                    painter: _DashedCirclePainter(colorScheme.onSurfaceVariant),
                    child: Icon(Icons.add, size: 16, color: colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.themeColorCustom,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Hint(l10n.themeColorHintDots, maxWidth: 560),
      ],
    );
  }

  /// The light half's *rendered* value, not the seed — the same rule the
  /// swatch itself follows, so the number on the tooltip is a colour the app
  /// actually paints.
  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {required this.maxWidth});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: AppType.looseHeight,
            ),
      ),
    );
  }
}

/// One preset as a picture of itself in both modes — design `20b`.
///
/// 162 wide: a 6px shell (radius 14) around a 148×96 preview (radius 10)
/// split down the middle. The left half is the *light* panel with the light
/// scheme's accent on it, the right half the *dark* panel with the dark
/// scheme's — always, whatever mode the app is in. Only the shell follows the
/// current theme: hover borders it in the accent ring, selection adds the
/// accent wash and a tick, keyboard focus draws a 2px accent ring outside a
/// 2px gap of panel colour.
///
/// In light mode the left half is the same colour as the panel it sits on,
/// so it takes a 1px inset hairline to keep its edge; dark mode does not,
/// because the right half is already darker than the panel and the two halves
/// separate on their own.
class ThemeAccentPreviewCard extends StatefulWidget {
  const ThemeAccentPreviewCard({
    super.key,
    required this.accent,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final ThemeAccent accent;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  static const double width = 162;
  static const double _shellPadding = 6;
  static const double previewHeight = 96;

  @override
  State<ThemeAccentPreviewCard> createState() => _ThemeAccentPreviewCardState();
}

class _ThemeAccentPreviewCardState extends State<ThemeAccentPreviewCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ColorScheme light = buildAppColorScheme(accent: widget.accent, brightness: Brightness.light);
    final ColorScheme dark = buildAppColorScheme(accent: widget.accent, brightness: Brightness.dark);
    final bool selected = widget.selected;

    return InkWell(
      onTap: widget.onTap,
      onHover: (v) => setState(() => _hovered = v),
      onFocusChange: (v) => setState(() => _focused = v),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
        width: ThemeAccentPreviewCard.width,
        padding: const EdgeInsets.all(ThemeAccentPreviewCard._shellPadding),
        decoration: BoxDecoration(
          color: selected ? colorScheme.accentTint : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          // Hover borrows only the ring: the wash is selection's own signal,
          // and sharing it would let the two states blur together in a scan.
          border: Border.all(
            color: selected || _hovered ? colorScheme.accentRing : Colors.transparent,
          ),
          // The focus ring, outside the shell: 2px of panel colour and then
          // 2px of accent, so on a selected card the three rings read in
          // order from the inside — 32% edge, gap, solid — without any one
          // swallowing another. Painted as spread-only shadows because that
          // is the one way to draw outside a box without a second widget.
          boxShadow: _focused
              ? [
                  BoxShadow(color: colorScheme.primary, spreadRadius: 4),
                  BoxShadow(color: colorScheme.surface, spreadRadius: 2),
                ]
              : const [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                height: ThemeAccentPreviewCard.previewHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: _PreviewHalf(
                        scheme: light,
                        hairline: colorScheme.brightness == Brightness.light,
                      ),
                    ),
                    Expanded(child: _PreviewHalf(scheme: dark, hairline: false)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 7, 4, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: selected ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  if (selected) Icon(Icons.check, size: 14, color: colorScheme.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One mode's half of the preview: a filled button, a switch and a selected
/// row, each reduced to its shape, in the shades that mode really uses.
///
/// Every colour here comes from the *scheme passed in*, not the ambient
/// theme — the half is a picture of another theme, which is the point.
class _PreviewHalf extends StatelessWidget {
  const _PreviewHalf({required this.scheme, required this.hairline});

  final ColorScheme scheme;
  final bool hairline;

  @override
  Widget build(BuildContext context) {
    final pill = BorderRadius.circular(999);

    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      foregroundDecoration:
          hairline ? BoxDecoration(border: Border.all(color: scheme.outlineVariant)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主色实底 — the CTA, with its label as a bar of `onPrimary`.
          Container(
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Container(
              width: 26,
              height: 3,
              decoration: BoxDecoration(color: scheme.onPrimary, borderRadius: pill),
            ),
          ),
          const SizedBox(height: 9),
          // 主色纯色 — a switch in its on state.
          Container(
            width: 28,
            height: 16,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: scheme.primary, borderRadius: pill),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: scheme.onPrimary, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(height: 9),
          // 主色 12% + 主色深 — a selected list row.
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: scheme.accentTint,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: scheme.onAccentTint, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(color: scheme.onAccentTint, borderRadius: pill),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The "custom colour" placeholder's dashed ring.
class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path circle = Path()
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - 0.5));
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const double dash = 3, gap = 3;
    for (final metric in circle.computeMetrics()) {
      for (double d = 0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}
