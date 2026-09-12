import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_semantic_colors.dart';
import '../core/app_theme.dart';
import '../core/constants.dart';
import '../core/custom_accent.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../core/theme_accent.dart';
import '../l10n/app_localizations.dart';
import 'app_button.dart';
import 'app_dialog.dart';
import 'app_field_size.dart';
import 'app_section_label.dart';
import 'app_switch.dart';
import 'dual_tone_swatch.dart';

/// The theme-colour chooser on the appearance page — design `E1 · 1a / 1b / 1e`.
///
/// Two forms of the same control, picked by width:
///
/// - **Desktop and tablet: preview cards** (`1a`). Each card is a miniature of
///   both modes side by side — a filled button, a switch and a selected row,
///   drawn in the exact shade each mode will use, with that shade's value — so
///   the dark half of a pair can be judged *before* it is chosen.
/// - **Mobile: dual-tone dots** (`1e`). Four per row, two rows; the pair's
///   values are on the long-press tooltip instead of in the picture.
///
/// Both end in **Custom…**, which opens [showCustomAccentDialog] — but only
/// when the caller passes [onCustomSeed]; without it the tile is not drawn.
///
/// Stateless on purpose: it reports the chosen preset's *key* (or the custom
/// seed) and lets the caller persist it, so it can be photographed by the
/// gallery and tested without an [AppState].
class ThemeAccentPicker extends StatelessWidget {
  const ThemeAccentPicker({
    super.key,
    required this.selected,
    required this.onSelect,
    this.customSeed,
    this.onCustomSeed,
  });

  /// The pair currently in use — compared by value against each preset.
  final ThemeAccent selected;

  /// Called with the [AppConstants.presetThemes] key the user picked.
  final ValueChanged<String> onSelect;

  /// The seed of the custom colour in use, if [selected] is one. Seeds the
  /// dialog; null opens it on the current accent.
  final Color? customSeed;

  /// Called with the seed the custom-colour dialog was applied with.
  final ValueChanged<Color>? onCustomSeed;

  bool get _customActive =>
      !AppConstants.presetThemes.values.contains(selected);

  Future<void> _openCustom(BuildContext context) async {
    final Color? seed = await showCustomAccentDialog(
      context,
      initialSeed: customSeed ?? selected.light,
    );
    if (seed != null) onCustomSeed?.call(seed);
  }

  @override
  Widget build(BuildContext context) {
    return Responsive.isMobile(context) ? _DotGrid(picker: this) : _CardGrid(picker: this);
  }
}

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
        LayoutBuilder(builder: (context, constraints) {
          final double width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 3 * ThemeAccentPreviewCard.width + 2 * _gap;
          final int columns = ((width + _gap) / (_minCardWidth + _gap)).floor().clamp(2, 3);
          final double cardWidth = ((width - _gap * (columns - 1)) / columns).floorToDouble();

          return Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (final MapEntry<String, ThemeAccent> preset in AppConstants.presetThemes.entries)
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
        }),
        const SizedBox(height: AppSpace.s10),
        _Hint(l10n.themeColorHintCards, maxWidth: 640),
      ],
    );
  }
}

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

/// The rendered value, not the seed — the same rule the swatch follows, so
/// every number shown is a colour the app actually paints.
String _hex(Color c) => CustomAccent.hex(c);

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
              height: AppType.proseHeight,
            ),
      ),
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

/// The ring's own colours — `CustomAccent.seedForHue` every 15°, closing back
/// on 0° — solved once, on first use. The ring, the desktop tile (unrolled
/// left to right) and the phone dot all paint from this one list, so the
/// colour under the ring's handle is the colour the tile promised.
final List<Color> _hueStops = [
  for (int h = 0; h <= 360; h += 15) CustomAccent.seedForHue(h.toDouble()),
];

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
      foregroundDecoration:
          hairline ? BoxDecoration(border: Border.all(color: scheme.outlineVariant)) : null,
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

// ── Custom colour ────────────────────────────────────────────────────────────

/// The custom theme colour flow — design `E1 · 1b`: pick a hue (the ring or a
/// hex value), see the pair derived from it drawn in real components, and the
/// measurements that decided it. Returns the seed to apply, or null.
///
/// The derivation is [CustomAccent.derive]; this only shows it. When white
/// cannot hold on the light half the result is not a failure: the button's
/// label becomes the hue's deep ink, which the banner shows as white struck
/// through and the ink that replaced it.
Future<Color?> showCustomAccentDialog(BuildContext context, {required Color initialSeed}) {
  return showDialog<Color>(
    context: context,
    animationStyle: appDialogAnimation(context),
    builder: (_) => _CustomAccentDialog(initialSeed: initialSeed),
  );
}

class _CustomAccentDialog extends StatefulWidget {
  const _CustomAccentDialog({required this.initialSeed});

  final Color initialSeed;

  @override
  State<_CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<_CustomAccentDialog> {
  late CustomAccentDerivation _derived = CustomAccent.derive(widget.initialSeed);
  late final TextEditingController _hexController =
      TextEditingController(text: CustomAccent.hex(widget.initialSeed));

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setSeed(Color seed, {bool fromField = false}) {
    if (seed.toARGB32() == _derived.seed.toARGB32()) return;
    setState(() => _derived = CustomAccent.derive(seed));
    if (!fromField) _hexController.text = CustomAccent.hex(seed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool failed = _derived.verdict == CustomAccentVerdict.failed;

    return AppDialog(
      icon: Icons.colorize,
      title: l10n.customAccentTitle,
      subtitle: CustomAccent.hex(_derived.seed),
      maxWidth: 520,
      scrollable: true,
      dividedHeading: false,
      onClose: () => Navigator.pop(context),
      content: LayoutBuilder(builder: (context, constraints) {
        final Widget picker = _buildPicker(context);
        final Widget result = _buildResult(context, l10n);
        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: SizedBox(width: 150, child: picker)),
              const SizedBox(height: AppSpace.s16),
              result,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: picker),
            const SizedBox(width: AppSpace.s16),
            Expanded(child: result),
          ],
        );
      }),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: l10n.apply,
          onPressed: failed ? null : () => Navigator.pop(context, _derived.seed),
        ),
      ],
    );
  }

  Widget _buildPicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hexStyle = textTheme.bodySmall?.mono;

    return Column(
      children: [
        _HueRing(
          hue: _derived.hue,
          seed: _derived.seed,
          onChanged: (hue) => _setSeed(CustomAccent.seedForHue(hue)),
        ),
        const SizedBox(height: AppSpace.s10),
        TextField(
          controller: _hexController,
          style: hexStyle,
          textAlignVertical: TextAlignVertical.center,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
            LengthLimitingTextInputFormatter(7),
          ],
          decoration: InputDecoration(
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            isDense: true,
            constraints: const BoxConstraints.tightFor(height: AppSize.control),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 8,
              vertical: pinnedFieldInset(context, hexStyle, AppSize.control),
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 8, right: 6),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _derived.seed,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          onChanged: (value) {
            final Color? seed = CustomAccent.parseHex(value);
            if (seed != null && value.replaceAll('#', '').length == 6) {
              _setSeed(seed, fromField: true);
            }
          },
        ),
        const SizedBox(height: AppSpace.s10),
        Text(
          AppLocalizations.of(context)!.customAccentHint,
          textAlign: TextAlign.center,
          style: textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurfaceVariant,
            height: AppType.proseHeight,
          ),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, AppLocalizations l10n) {
    final semantic = context.semantic;
    final colorScheme = Theme.of(context).colorScheme;
    final CustomAccentVerdict verdict = _derived.verdict;

    final (Color bannerBg, Color bannerInk, Color bannerText, IconData bannerIcon, String message) =
        switch (verdict) {
      CustomAccentVerdict.passed => (
          semantic.successContainer,
          semantic.success,
          semantic.onSuccessContainer,
          Icons.check_circle,
          l10n.customAccentPassed,
        ),
      CustomAccentVerdict.inkFallback => (
          semantic.warningContainer,
          semantic.warning,
          semantic.onWarningContainer,
          Icons.warning_amber_rounded,
          l10n.customAccentInkFallback,
        ),
      CustomAccentVerdict.failed => (
          colorScheme.errorContainer,
          colorScheme.error,
          colorScheme.onErrorContainer,
          Icons.error_outline,
          l10n.customAccentFailed,
        ),
    };

    final AccentCheck white =
        _derived.checks.firstWhere((c) => c.kind == AccentCheckKind.whiteOnAccent);
    final AccentCheck? ink =
        _derived.checks.where((c) => c.kind == AccentCheckKind.inkOnAccent).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionLabel(l10n.customAccentDerived, padding: EdgeInsets.zero),
        const SizedBox(height: AppSpace.s10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PairPanel(accent: _derived.accent, brightness: Brightness.light)),
            const SizedBox(width: 8),
            Expanded(child: _PairPanel(accent: _derived.accent, brightness: Brightness.dark)),
          ],
        ),
        const SizedBox(height: AppSpace.s10),
        // What the primary button's label ended up as: white that holds, or
        // white struck out and the deep ink that took its place.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: bannerBg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(bannerIcon, size: AppSize.iconSm, color: bannerInk),
              ),
              const SizedBox(width: AppSpace.s6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: bannerText,
                            height: AppType.proseHeight,
                          ),
                    ),
                    const SizedBox(height: AppSpace.s6),
                    Wrap(
                      spacing: AppSpace.s6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CheckChip(check: white),
                        _Ratio(check: white),
                        if (ink != null) ...[
                          Icon(Icons.arrow_forward, size: AppSize.iconSm, color: bannerInk),
                          _CheckChip(check: ink),
                          _Ratio(check: ink),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.s10),
        for (final AccentCheck check in _derived.checks)
          if (check.kind != AccentCheckKind.whiteOnAccent && check.kind != AccentCheckKind.inkOnAccent)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    check.brightness == Brightness.light ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                    size: AppSize.iconSm,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  _CheckChip(check: check),
                  const Spacer(),
                  _Ratio(check: check),
                ],
              ),
            ),
      ],
    );
  }
}

/// One brightness of the derived pair, drawn in that brightness's real theme
/// — a primary button, a switch and a selected row are the app's own widgets,
/// so the preview cannot promise what the app would not paint.
class _PairPanel extends StatelessWidget {
  const _PairPanel({required this.accent, required this.brightness});

  final ThemeAccent accent;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ThemeData theme = buildAppTheme(
      accent: accent,
      brightness: brightness,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    );

    return Theme(
      data: theme,
      child: Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return ExcludeFocus(
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(AppSpace.s10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          brightness == Brightness.light ? l10n.themeLight : l10n.themeDark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        _hex(scheme.primary),
                        style: textTheme.labelSmall?.mono.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s6),
                  AppButton(
                    label: l10n.processPrompt,
                    size: AppButtonSize.compact,
                    fullWidth: true,
                    onPressed: () {},
                  ),
                  const SizedBox(height: AppSpace.s6),
                  Row(
                    children: [
                      AppSwitch(value: true, onChanged: (_) {}),
                      const SizedBox(width: AppSpace.s6),
                      Expanded(
                        child: Container(
                          height: 24,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: scheme.accentTint,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            l10n.custom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(color: scheme.onAccentTint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A check as a picture of its own pairing: a glyph in the foreground on the
/// ground it is measured against — or, for the outline check, a 1.5px ring.
class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.check});

  final AccentCheck check;

  @override
  Widget build(BuildContext context) {
    final bool stroke = check.kind == AccentCheckKind.strokeOnCanvas;
    return Container(
      width: 36,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: check.background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: stroke
          ? Container(
              width: 20,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: check.foreground, width: 1.5),
              ),
            )
          : Icon(Icons.text_fields, size: AppSize.iconSm, color: check.foreground),
    );
  }
}

/// A ratio in mono, with a tick or a cross in the success or warning ink.
class _Ratio extends StatelessWidget {
  const _Ratio({required this.check});

  final AccentCheck check;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final Color ink = check.passes ? semantic.onSuccessContainer : semantic.onWarningContainer;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${check.ratio.toStringAsFixed(1)}:1',
          style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                fontWeight: FontWeight.w400,
                color: ink,
              ),
        ),
        const SizedBox(width: 2),
        Icon(check.passes ? Icons.check : Icons.close, size: 12, color: ink),
      ],
    );
  }
}

/// The hue ring — `1b`: 130px, a 16px band of the hues at the chroma and
/// tone a picked hue is seeded at, and a 14px handle with a white 3px edge.
///
/// Drag or tap anywhere to set the hue by angle; arrow keys step it by 5°.
class _HueRing extends StatefulWidget {
  const _HueRing({required this.hue, required this.seed, required this.onChanged});

  final double hue;
  final Color seed;
  final ValueChanged<double> onChanged;

  static const double size = 130;
  static const double band = 16;

  @override
  State<_HueRing> createState() => _HueRingState();
}

class _HueRingState extends State<_HueRing> {
  bool _focused = false;

  void _fromPosition(Offset local) {
    const Offset centre = Offset(_HueRing.size / 2, _HueRing.size / 2);
    final Offset d = local - centre;
    if (d.distance < 4) return;
    final double degrees = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    widget.onChanged(degrees.roundToDouble());
  }

  void _step(double by) => widget.onChanged(((widget.hue + by) % 360 + 360) % 360);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: l10n.customColor,
      value: '${widget.hue.round()}°',
      increasedValue: '${((widget.hue + 5) % 360).round()}°',
      decreasedValue: '${((widget.hue - 5 + 360) % 360).round()}°',
      onIncrease: () => _step(5),
      onDecrease: () => _step(-5),
      child: Focus(
        onFocusChange: (v) => setState(() => _focused = v),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _step(5);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _step(-5);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onPanDown: (d) => _fromPosition(d.localPosition),
          onPanUpdate: (d) => _fromPosition(d.localPosition),
          child: SizedBox.square(
            dimension: _HueRing.size,
            child: CustomPaint(
              painter: _HueRingPainter(
                hue: widget.hue,
                seed: widget.seed,
                focusRing: _focused ? colorScheme.accentRing : null,
                stops: _hueStops,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HueRingPainter extends CustomPainter {
  const _HueRingPainter({
    required this.hue,
    required this.seed,
    required this.focusRing,
    required this.stops,
  });

  final double hue;
  final Color seed;
  final Color? focusRing;
  final List<Color> stops;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - _HueRing.band / 2;
    final Rect rect = Rect.fromCircle(center: c, radius: size.shortestSide / 2);

    if (focusRing != null) {
      canvas.drawCircle(
        c,
        size.shortestSide / 2 - _HueRing.band - 3,
        Paint()
          ..color = focusRing!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = SweepGradient(colors: stops).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _HueRing.band,
    );

    final double a = hue * math.pi / 180;
    final Offset handle = c + Offset(math.cos(a), math.sin(a)) * radius;
    canvas.drawCircle(
      handle.translate(0, 1),
      8.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(handle, 7, Paint()..color = Colors.white);
    canvas.drawCircle(handle, 4, Paint()..color = seed);
  }

  @override
  bool shouldRepaint(_HueRingPainter old) =>
      old.hue != hue || old.seed != seed || old.focusRing != focusRing;
}
