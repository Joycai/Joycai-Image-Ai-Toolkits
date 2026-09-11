import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'app_theme.dart';
import 'constants.dart';
import 'design_tokens.dart';
import 'theme_accent.dart';

/// A theme colour the user picked rather than one of the presets — design
/// `00 · 1g` / `E1 · 1b`.
///
/// The derivation is the rule the presets were tuned by
/// (`docs/architecture/design-tokens.md` §1), applied to any seed:
///
/// - **Light half**: the seed's hue and chroma at tone 44 — the nearest tone
///   white text holds on. Amber-to-yellow hues are brown at 44, so that band
///   ([isWarm]) sits at tone 55 instead and the button label falls back to the
///   hue's own tone-10 ink, exactly as the Orange preset does.
///   [ThemeAccent.onLight] already makes that call; nothing here special-cases
///   the button.
/// - **Dark half**: the seed itself when it is already at least tone 62,
///   otherwise the seed at tone 62 — then lifted a tone at a time until it
///   reads on the dark card and carries its tone-10 ink, both at 4.5:1.
///
/// Stored as the **seed**, not as the pair ([storageValue]). Re-deriving on
/// load is the same promise a preset key makes: a later retune of this rule
/// reaches every user who picked a custom colour.
///
/// Pure: no widgets, no state. The greys the checks measure against are read
/// from [buildAppColorScheme], which never lets the accent touch them.
class CustomAccent {
  CustomAccent._();

  /// Prefix of a `theme_accent` setting that holds a custom seed rather than a
  /// preset key.
  static const String storagePrefix = 'custom:';

  /// What `theme_accent` stores for [seed]: `custom:#RRGGBB`.
  static String storageValue(Color seed) => '$storagePrefix${hex(seed)}';

  /// The seed in a `theme_accent` value, or null when it names a preset (or
  /// nothing readable).
  static Color? parseStorageValue(String? value) {
    if (value == null || !value.startsWith(storagePrefix)) return null;
    return parseHex(value.substring(storagePrefix.length));
  }

  /// `#RRGGBB`, `RRGGBB` or the three-digit short form; null otherwise.
  static Color? parseHex(String input) {
    String s = input.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
    if (s.length != 6) return null;
    final int? v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  /// Upper-case `#RRGGBB`, alpha dropped.
  static String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Chroma and tone a hue picked on the colour ring is seeded at. Vivid
  /// enough to be the colour the ring shows under the handle; the derivation
  /// then moves the tone, never the hue.
  static const double ringChroma = 48;
  static const double ringTone = 62;

  /// The seed for a [hue] (HCT degrees) picked on the ring.
  static Color seedForHue(double hue) =>
      Color(Hct.from(hue % 360, ringChroma, ringTone).toInt());

  /// [color]'s HCT hue, in degrees.
  static double hueOf(Color color) => Hct.fromInt(color.toARGB32()).hue;

  /// Where tone 44 stops being the hue and becomes brown — amber through
  /// yellow-green. Orange (`#FF9800`) sits inside it; deep orange and lime
  /// sit on either side and survive tone 44.
  static const double warmBandStart = 48;
  static const double warmBandEnd = 112;

  /// The light half's tone inside the warm band. The same tone the Orange
  /// preset was tuned to: the lightest that still holds its own dark ink at
  /// AA and stands as an outline on the canvas.
  static const double warmLightTone = 55;

  /// The dark half is never lifted past this: above it the colour is a
  /// pastel, which is the failure the pair exists to avoid.
  static const double darkToneCeiling = 80;

  static bool isWarm(double hue) => hue >= warmBandStart && hue < warmBandEnd;

  /// Derives the pair for [seed] and measures it.
  static CustomAccentDerivation derive(Color seed) {
    final Color opaque = Color(seed.toARGB32() | 0xFF000000);
    final Hct hct = Hct.fromInt(opaque.toARGB32());
    final bool warm = isWarm(hct.hue);

    final double lightTone = warm ? warmLightTone : ThemeAccent.derivedLightTone;
    final Color light = _atTone(hct, lightTone);

    // The greys do not follow the accent, so any scheme will do for them.
    final ThemeAccent reference = AppConstants.presetThemes[AppConstants.defaultThemeAccentKey]!;
    final ColorScheme darkNeutrals = buildAppColorScheme(accent: reference, brightness: Brightness.dark);

    double darkTone = math.max(hct.tone, ThemeAccent.derivedDarkTone);
    Color dark = hct.tone >= ThemeAccent.derivedDarkTone ? opaque : _atTone(hct, darkTone);
    bool darkHolds(Color c) =>
        contrast(c, darkNeutrals.surfaceContainerHigh) >= 4.5 &&
        contrast(_atTone(Hct.fromInt(c.toARGB32()), 10), c) >= 4.5;
    while (!darkHolds(dark) && darkTone < darkToneCeiling) {
      darkTone = math.min(darkTone + 1, darkToneCeiling);
      dark = _atTone(hct, darkTone);
    }

    final ThemeAccent accent = ThemeAccent(light: light, dark: dark);
    final ColorScheme ls = buildAppColorScheme(accent: accent, brightness: Brightness.light);
    final ColorScheme ds = buildAppColorScheme(accent: accent, brightness: Brightness.dark);

    const Color white = Color(0xFFFFFFFF);
    final List<Color> lightSurfaces = [
      ls.surfaceContainer,
      ls.surfaceContainerLow,
      ls.surface,
      ls.surfaceContainerHigh,
    ];
    // The deep ink's weakest surface is the one to report.
    Color weakest = lightSurfaces.first;
    for (final Color s in lightSurfaces) {
      if (contrast(ls.onAccentTint, s) < contrast(ls.onAccentTint, weakest)) weakest = s;
    }

    final bool whiteHolds = ls.onPrimary.toARGB32() == white.toARGB32();

    return CustomAccentDerivation(
      seed: opaque,
      accent: accent,
      hue: hct.hue,
      warm: warm,
      whiteHolds: whiteHolds,
      checks: [
        AccentCheck(
          kind: AccentCheckKind.whiteOnAccent,
          brightness: Brightness.light,
          foreground: white,
          background: light,
          threshold: 4.5,
          // Informational when it fails: the ink below takes over, which is
          // the designed outcome rather than a fault.
          required: false,
        ),
        if (!whiteHolds)
          AccentCheck(
            kind: AccentCheckKind.inkOnAccent,
            brightness: Brightness.light,
            foreground: ls.onPrimary,
            background: light,
            threshold: 4.5,
          ),
        AccentCheck(
          kind: AccentCheckKind.deepInkOnSurfaces,
          brightness: Brightness.light,
          foreground: ls.onAccentTint,
          background: weakest,
          threshold: 4.5,
        ),
        AccentCheck(
          kind: AccentCheckKind.strokeOnCanvas,
          brightness: Brightness.light,
          foreground: light,
          background: ls.surfaceContainer,
          threshold: 3,
        ),
        AccentCheck(
          kind: AccentCheckKind.darkOnCard,
          brightness: Brightness.dark,
          foreground: dark,
          background: ds.surfaceContainerHigh,
          threshold: 4.5,
        ),
        AccentCheck(
          kind: AccentCheckKind.inkOnDarkAccent,
          brightness: Brightness.dark,
          foreground: ds.onPrimary,
          background: dark,
          threshold: 4.5,
        ),
      ],
    );
  }

  /// WCAG contrast ratio between two opaque colours.
  static double contrast(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  static Color _atTone(Hct hct, double tone) => Color(Hct.from(hct.hue, hct.chroma, tone).toInt());
}

/// What a check measures. Each pairs a foreground with the ground it has to
/// read on.
enum AccentCheckKind {
  /// White label on the light half — the primary button.
  whiteOnAccent,

  /// The hue's tone-10 ink on the light half, when white does not hold.
  inkOnAccent,

  /// The deep ink (`--p-deep`) on the weakest light surface, column to card.
  deepInkOnSurfaces,

  /// The light half as a 1px outline on the canvas.
  strokeOnCanvas,

  /// The dark half as text on the dark card.
  darkOnCard,

  /// The dark half's own ink on it.
  inkOnDarkAccent,
}

/// One measured pairing.
@immutable
class AccentCheck {
  const AccentCheck({
    required this.kind,
    required this.brightness,
    required this.foreground,
    required this.background,
    required this.threshold,
    this.required = true,
  });

  final AccentCheckKind kind;

  /// Which half of the pair this was measured in.
  final Brightness brightness;
  final Color foreground;
  final Color background;
  final double threshold;

  /// False for a check whose failure is an outcome, not a fault.
  final bool required;

  double get ratio => CustomAccent.contrast(foreground, background);
  bool get passes => ratio >= threshold;
}

/// How a derived pair came out.
enum CustomAccentVerdict {
  /// Every check holds, and the button keeps its white label.
  passed,

  /// White cannot hold on the light half; the button wears the hue's deep
  /// ink instead, and every other check holds.
  inkFallback,

  /// A required check fails even after the lift. Not applied.
  failed,
}

/// A seed, the pair derived from it, and the measurements.
@immutable
class CustomAccentDerivation {
  const CustomAccentDerivation({
    required this.seed,
    required this.accent,
    required this.hue,
    required this.warm,
    required this.whiteHolds,
    required this.checks,
  });

  final Color seed;
  final ThemeAccent accent;

  /// HCT hue of [seed], in degrees.
  final double hue;

  /// Whether the light half left tone 44 for the warm band's tone.
  final bool warm;

  /// Whether the light half's button label is white.
  final bool whiteHolds;

  final List<AccentCheck> checks;

  CustomAccentVerdict get verdict {
    if (checks.any((c) => c.required && !c.passes)) return CustomAccentVerdict.failed;
    return whiteHolds ? CustomAccentVerdict.passed : CustomAccentVerdict.inkFallback;
  }
}
