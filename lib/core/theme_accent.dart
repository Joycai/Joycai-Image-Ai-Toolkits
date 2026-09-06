import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// A theme colour as the *pair* it has to be: one accent for light mode and
/// a separately tuned one for dark.
///
/// macOS and Windows both ship their accents this way — "Pink" is one name
/// for two hexes, and the dark one is a little lighter and a little more
/// saturated than the light one, because the same ink that carries weight on
/// white is a dull smear on near-black. Before this type the app had one seed
/// and let Material derive both halves from it, which put the dark accent at
/// tone 80: a pastel wash of the colour the user picked, on every checkbox,
/// switch, focus ring and selected row. The spec's own dark frame (`10b`)
/// draws its accent at tone 60, not 80, and this is how that gets honoured
/// for every preset instead of only the blue one.
///
/// Both halves are **finished colours**, drawn verbatim as `primary` in their
/// brightness. Each was tuned on its own ramp — the light one against white
/// and the light canvas, the dark one against the dark card — and it would be
/// pointless to tune a colour and then let a palette pick a different one.
/// The palette's remaining roles (containers, secondary, tertiary) are still
/// grown from the half, so their hue follows.
///
/// Neither half is the raw Material seed it started from. Light used to be:
/// the scheme grew from it and took Material's tone-40 `primary`, which is
/// the *vibrant* palette's tone 40 — at maximum chroma. Indigo came out
/// `#1242FF`, deep purple `#7801FF`, blue-grey a saturated `#006783`: the
/// user picked a colour and the app rendered a neon of it. The light half is
/// now the seed's own hue and chroma at tone 44 — as close to the picked
/// colour as white text on it allows (≥ 5.5:1; the seed itself, `#4A72E8`
/// on white, is 4.3:1).
///
/// Presets live in `AppConstants.presetThemes`; [ThemeAccent.fromSeed] is for
/// a colour that has no hand-tuned halves — tests, and the screenshot
/// harness — and is also the starting point each preset's hexes were tuned
/// from.
@immutable
class ThemeAccent {
  const ThemeAccent({required this.light, required this.dark});

  /// The accent light mode draws, as-is, as `primary`. Also the seed the
  /// rest of the light palette is grown from.
  final Color light;

  /// The accent dark mode draws, as-is, as `primary`. Also the seed the
  /// rest of the dark palette is grown from.
  final Color dark;

  /// Where [fromSeed] puts the light accent's tone (HCT, so L\*).
  ///
  /// Chosen against white and the light canvas, not by taste: at 44 white
  /// text on the accent is ≥ 5.5:1 and the accent as text on the canvas
  /// (`#ECEFF8`) is ≥ 4.8:1. At 47 the canvas figure drops under AA; at 40
  /// — Material's own choice — both hold with more room, but every colour is
  /// four tones further from the one the user picked. 44 keeps the margin
  /// and gives the tones back.
  static const double derivedLightTone = 44;

  /// Where [fromSeed] puts the dark accent's tone (HCT, so L\*).
  ///
  /// Chosen against the dark ramp in `app_theme.dart`, not by taste: at 62
  /// the accent reads as text on every dark surface up to the card
  /// (`surfaceContainerHigh`, ≥ 4.7:1) and still carries a tone-10 ink on it
  /// at ≥ 5.4:1 — which is what a count badge or a selected chip needs. At
  /// 58 both of those are on the AA floor; at 70 the colour is a pastel
  /// again, which is the failure this type exists to get out of. The spec's
  /// own dark blue sits at 60.
  static const double derivedDarkTone = 62;

  /// A pair from one seed: both halves keep the seed's hue and chroma; the
  /// light one lowers its tone to at most [derivedLightTone], the dark one
  /// lifts it to at least [derivedDarkTone].
  ///
  /// "At most" and "at least": a seed already on the legible side of a
  /// threshold is kept where it is rather than pushed through it. Material's
  /// orange is tone 72 and stays there in dark — the lift is for legibility
  /// on a dark ground, which a lighter seed already has — and indigo is tone
  /// 38 and stays there in light, for the same reason under white.
  factory ThemeAccent.fromSeed(Color seed) {
    final Hct hct = Hct.fromInt(seed.toARGB32());
    return ThemeAccent(
      light: hct.tone <= derivedLightTone ? seed : _atTone(hct, derivedLightTone),
      dark: hct.tone >= derivedDarkTone ? seed : _atTone(hct, derivedDarkTone),
    );
  }

  /// The half this brightness draws.
  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Ink drawn *on* [light] — the CTA's label, a badge's digits.
  ///
  /// White, which is the design's rule for light mode and the reason the
  /// light half sits at tone 44 rather than at the seed: the tone is what
  /// makes white legible on it, so white is the ink.
  Color get onLight => const Color(0xFFFFFFFF);

  /// Ink drawn *on* [dark] — a badge's digits, a selected chip's label.
  ///
  /// Tone 10 of the accent's own hue: near-black, faintly tinted. Not white.
  /// A dark accent lives at tone ~62, and white on it is ~3:1 — the classic
  /// mid-tone trap, where neither white nor black reads well and dark wins
  /// only narrowly. Material's own dark scheme makes the same call (tone 20
  /// on tone 80); this is that idiom moved down the ladder with the accent.
  Color get onDark => _atTone(Hct.fromInt(dark.toARGB32()), 10);

  /// Text drawn on a 12% wash of [dark] — a selected tab's label, a running
  /// badge, a section caption. See `AppAccent.onAccentTint`.
  ///
  /// Tone 80 at the accent's *own* chroma, not the vibrant palette's. The
  /// vibrant variant grows its primary palette at maximum chroma, so its
  /// tone 80 for a teal seed is `#00DECB` — a neon that no longer resembles
  /// the calmer accent the user picked and the wash it sits on. Same hue,
  /// same chroma, eighteen tones lighter: the label reads as the accent
  /// speaking, not as a different colour.
  Color get darkOnTint => _atTone(Hct.fromInt(dark.toARGB32()), 80);

  /// Text drawn on a 12% wash of [light] — the light-mode counterpart of
  /// [darkOnTint]. See `AppAccent.onAccentTint`.
  ///
  /// Tone 30 at the accent's own chroma, for the same reason [darkOnTint]
  /// is at its own: the vibrant palette's tone 30 is at maximum chroma, and
  /// next to a light half that is not (blue-grey is chroma 20) it is a
  /// different colour, not a darker one. Fourteen tones below the accent,
  /// like the spec's 主色深 (`#3355C4` ≈ 40 under `#4A72E8` ≈ 51).
  Color get lightOnTint => _atTone(Hct.fromInt(light.toARGB32()), 30);

  static Color _atTone(Hct hct, double tone) =>
      Color(Hct.from(hct.hue, hct.chroma, tone).toInt());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeAccent &&
          other.light.toARGB32() == light.toARGB32() &&
          other.dark.toARGB32() == dark.toARGB32();

  @override
  int get hashCode => Object.hash(light.toARGB32(), dark.toARGB32());

  @override
  String toString() =>
      'ThemeAccent(light: ${_hex(light)}, dark: ${_hex(dark)})';

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
