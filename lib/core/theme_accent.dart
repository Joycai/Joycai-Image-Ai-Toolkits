import 'dart:math' as math;

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
/// The two halves are used differently, on purpose:
///
/// - [light] is a **seed**. [buildAppColorScheme] grows a light scheme from
///   it and draws `primary` at tone 40 (see `buttonFillScheme` for why a fill
///   under white text cannot be the seed itself — `#4A72E8` on white is
///   4.3:1, a hair under AA, and Material's tone 40 is what fixes that).
/// - [dark] is **the accent**, drawn as-is as dark `primary`. It is the value
///   a designer tuned looking at it on the dark canvas, and it would be
///   pointless to tune a colour and then let a palette pick a different one.
///   The dark palette's remaining roles (containers, secondary, tertiary) are
///   still grown from it, so their hue follows.
///
/// Presets live in `AppConstants.presetThemes`; [ThemeAccent.fromSeed] is for
/// a colour that has no hand-tuned dark half — tests, and the screenshot
/// harness — and is also the starting point each preset's dark hex was tuned
/// from.
@immutable
class ThemeAccent {
  const ThemeAccent({required this.light, required this.dark});

  /// The seed the light scheme is grown from.
  final Color light;

  /// The accent dark mode draws, as-is, as `primary`.
  final Color dark;

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

  /// A pair from one seed: the dark half keeps the seed's hue and chroma and
  /// lifts its tone to at least [derivedDarkTone].
  ///
  /// "At least": a seed that is already lighter than that (Material's orange
  /// is tone 72) is kept where it is rather than darkened — the point of the
  /// lift is legibility on a dark ground, and a lighter seed already has it.
  factory ThemeAccent.fromSeed(Color seed) {
    final Hct hct = Hct.fromInt(seed.toARGB32());
    return ThemeAccent(
      light: seed,
      dark: _atTone(hct, math.max(hct.tone, derivedDarkTone)),
    );
  }

  /// The half this brightness draws.
  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

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
