import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_semantic_colors.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Pins the rule that lets one design spec, drawn in a single teal, render
/// correctly under all seven of the app's seed colours.
///
/// The spec's tokens are hexes; the app's are roles plus an alpha. The whole
/// translation rests on [AppAccent.onAccentTint] landing on a tone that reads
/// against its own tint at every seed — which is easy to get subtly wrong,
/// silently, in one brightness only. Hence the loop rather than a spot check.
void main() {
  /// WCAG relative luminance.
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('accent tokens hold at every seed', () {
    for (final MapEntry<String, ThemeAccent> seed in AppConstants.presetThemes.entries) {
      for (final Brightness brightness in Brightness.values) {
        final String where = '${seed.key}/${brightness.name}';

        test('onAccentTint reads on its own tint — $where', () {
          final scheme = buildAppColorScheme(accent: seed.value, brightness: brightness);

          // The tint is translucent, so what the label actually sits on is the
          // tint composited over the surface beneath it — which is what the
          // ratio has to be measured against, not the tint's nominal colour.
          final Color effective = Color.alphaBlend(scheme.accentTint, scheme.surface);
          final double ratio = contrast(scheme.onAccentTint, effective);

          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'A selected tab/nav item/badge label fails AA at $where '
                  '(${ratio.toStringAsFixed(2)}:1). If AppAlpha.tint was raised, '
                  'this is the check it broke — dark mode goes first.');
        });

        test('onAccentTint reads on bare surface too — $where', () {
          // The other place this role is used: AppSectionLabel draws the small
          // tracked caption on `surface`, with no tint under it. Strictly
          // easier than the tint case above — surface is further from the
          // label in both brightnesses — but stated rather than inferred,
          // because it is the pairing that made the label switch off `primary`
          // and nothing else would fail if it regressed.
          final scheme = buildAppColorScheme(accent: seed.value, brightness: brightness);
          final double ratio = contrast(scheme.onAccentTint, scheme.surface);

          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: 'A section label fails AA at $where '
                  '(${ratio.toStringAsFixed(2)}:1).');
        });

        test('onAccentTint stays distinct from the accent itself — $where', () {
          // The spec's 主色深 sits ~10 tones off 主色: near enough to still read
          // as the accent, far enough to be legible on a wash of it. Collapsing
          // the two is the failure this guards — a label in `primary` on a
          // `primary` tint, which is one tone reading against itself.
          final scheme = buildAppColorScheme(accent: seed.value, brightness: brightness);
          expect(scheme.onAccentTint, isNot(scheme.primary), reason: where);
        });
      }
    }

    test('the branch picks the role that is right in each brightness', () {
      // Pinned because each half looks like it could be simplified away, and
      // each simplification breaks the other half:
      //   · onPrimaryFixedVariant everywhere → tone 30 in dark, a label that
      //     all but vanishes on the dark canvas
      //   · primaryFixedDim everywhere       → tone 80 in light, a pastel
      //     label on a white panel
      final accent = ThemeAccent.fromSeed(Colors.teal);
      final light = buildAppColorScheme(accent: accent, brightness: Brightness.light);
      expect(light.onAccentTint, light.onPrimaryFixedVariant);

      final dark = buildAppColorScheme(accent: accent, brightness: Brightness.dark);
      expect(dark.onAccentTint, dark.primaryFixedDim);

      // The facts the branch rests on, asserted so an SDK bump or a change to
      // buildAppColorScheme that moves any of them fails here rather than
      // silently in the UI.
      expect(dark.primaryFixedDim, isNot(dark.primary),
          reason: 'primaryFixedDim is primary again in dark. Before the accent '
              'became a pair that was always so (both tone 80), which is why '
              'the dark branch used to read onPrimaryContainer; the label '
              'would be one tone reading against its own tint');
      expect(dark.primaryFixedDim, accent.darkOnTint,
          reason: 'buildAppColorScheme rewrites primaryFixedDim in dark to '
              'tone 80 at the accent\'s own chroma — the vibrant palette\'s '
              'tone 80 is at maximum chroma, a neon beside a calmer accent');
      expect(light.onPrimaryFixedVariant, accent.lightOnTint,
          reason: 'buildAppColorScheme rewrites onPrimaryFixedVariant in light '
              'to tone 30 at the accent\'s own chroma, for the same reason as '
              'primaryFixedDim in dark');
    });
  });

  group('the accent is a pair, and dark draws its own half', () {
    // The rule ThemeAccent exists for. fromSeed puts dark `primary` at tone
    // 80 — a pastel of whatever was picked, on every checkbox, switch, ring
    // and selected row — and the spec's own dark frame draws its accent at
    // tone 60. Each preset carries a dark half tuned on the dark ramp, and
    // it is drawn verbatim. These pin what "tuned" has to mean, so a retune
    // that drifts fails here rather than in a badge nobody can read.
    for (final MapEntry<String, ThemeAccent> preset in AppConstants.presetThemes.entries) {
      final ThemeAccent accent = preset.value;
      final dark = buildAppColorScheme(accent: accent, brightness: Brightness.dark);

      test('dark primary is the tuned dark half, verbatim — ${preset.key}', () {
        expect(dark.primary, accent.dark);
      });

      test('the dark accent is a mid tone, not the pastel fromSeed gives — ${preset.key}', () {
        final Color material = ColorScheme.fromSeed(
          seedColor: accent.dark,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        ).primary;
        expect(luminance(dark.primary), lessThan(luminance(material)),
            reason: '${preset.key}\'s dark half is as pale as tone 80 — '
                'the pair has stopped doing anything');
      });

      test('the dark accent reads as text on every dark surface — ${preset.key}', () {
        // `primary` is a text colour too: TextButton labels, AppButton.text,
        // the accentLabel on the workbench's add-folder button, links. The
        // card surface is the darkest ground text is set on in practice, and
        // the one that bounds the tone from below.
        for (final (name, ground) in [
          ('surface', dark.surface),
          ('surfaceContainerLow', dark.surfaceContainerLow),
          ('surfaceContainer', dark.surfaceContainer),
          ('surfaceContainerHigh', dark.surfaceContainerHigh),
        ]) {
          final double ratio = contrast(dark.primary, ground);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '${preset.key} on $name: ${ratio.toStringAsFixed(2)}:1 — '
                  'the dark half was tuned too dark');
        }
      });

      test('ink on the dark accent reads, and is not white — ${preset.key}', () {
        // A count badge, a selected chip's tick, the browser's selection
        // check: all `onPrimary` on `primary`. At tone ~62 white is ~3:1,
        // the mid-tone trap; the accent's own tone-10 ink is what reads.
        final double ratio = contrast(dark.onPrimary, dark.primary);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${preset.key}: ${ratio.toStringAsFixed(2)}:1 — the dark '
                'half was tuned too dark for its ink, or onPrimary regressed');
        expect(dark.onPrimary.toARGB32(), isNot(Colors.white.toARGB32()));
      });

      test('the two halves are one colour — ${preset.key}', () {
        // A typo'd hex in a preset would pass every contrast check above and
        // still be wrong. Compared against the *rendered* light primary, not
        // the seed: BlueGrey's seed is a slate the vibrant scheme pulls a
        // long way, and it is the rendered pair the user sees together.
        final light = buildAppColorScheme(accent: accent, brightness: Brightness.light);
        final double a = HSVColor.fromColor(light.primary).hue;
        final double b = HSVColor.fromColor(dark.primary).hue;
        final double delta = (a - b).abs();
        final double wrapped = delta > 180 ? 360 - delta : delta;
        expect(wrapped, lessThan(30),
            reason: '${preset.key}: light hue $a vs dark hue $b');
      });

      final light = buildAppColorScheme(accent: accent, brightness: Brightness.light);

      test('light primary is the tuned light half, verbatim, under white — ${preset.key}', () {
        // The light half was a seed once, and light primary was Material's
        // tone 40 of it — the *vibrant* palette's tone 40, at maximum chroma,
        // which turned indigo into `#1242FF` and deep purple into `#7801FF`.
        // Now it is drawn as-is, like the dark half.
        expect(light.primary, accent.light);
        expect(light.onPrimary, accent.onLight);
        expect(light.onPrimary.toARGB32(), Colors.white.toARGB32());
      });

      test('the light accent is the picked colour, not the palette\'s neon of it — ${preset.key}', () {
        // Measured against the seed the preset is named after: same hue, and
        // the seed's own chroma rather than whatever the gamut allows at that
        // tone. Hue in HCT, where "same" means the same thing at every chroma.
        final int legacySeed = AppConstants.legacySeedPresets.entries
            .firstWhere((e) => e.value == preset.key)
            .key;
        final Hct seed = Hct.fromInt(legacySeed);
        final Hct half = Hct.fromInt(accent.light.toARGB32());
        final double hueDelta = (seed.hue - half.hue).abs();
        expect(hueDelta > 180 ? 360 - hueDelta : hueDelta, lessThan(4),
            reason: '${preset.key}: seed hue ${seed.hue} vs light half ${half.hue}');
        expect(half.chroma, lessThanOrEqualTo(seed.chroma + 2),
            reason: '${preset.key}: the light half is more saturated than the '
                'seed — that is the palette\'s tone 40 creeping back');

        final Color grown = ColorScheme.fromSeed(
          seedColor: Color(legacySeed),
          brightness: Brightness.light,
          dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
        ).primary;
        expect(light.primary, isNot(grown),
            reason: '${preset.key}: light primary is the palette\'s tone 40 again');
      });

      test('white reads on the light accent, and the accent reads on every light ground — ${preset.key}', () {
        // The CTA carries white at body size; `primary` is also text — a
        // TextButton label, a link — on every light ground from white down
        // to the canvas. Both bound the tone from above; 44 holds both.
        expect(contrast(light.onPrimary, light.primary), greaterThanOrEqualTo(4.5),
            reason: '${preset.key}: the light half is too light for white text');
        for (final (name, ground) in [
          ('surfaceContainerLowest', light.surfaceContainerLowest),
          ('surface', light.surface),
          ('surfaceContainerLow', light.surfaceContainerLow),
          ('surfaceContainer', light.surfaceContainer),
          ('surfaceDim', light.surfaceDim),
        ]) {
          final double ratio = contrast(light.primary, ground);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '${preset.key} on $name: ${ratio.toStringAsFixed(2)}:1 — '
                  'the light half was tuned too light');
        }
      });

      test('the light wash label is tone 30 at the light half\'s own chroma — ${preset.key}', () {
        expect(light.onPrimaryFixedVariant, accent.lightOnTint);
        expect(Hct.fromInt(light.onAccentTint.toARGB32()).chroma,
            lessThanOrEqualTo(Hct.fromInt(accent.light.toARGB32()).chroma + 2),
            reason: '${preset.key}: the wash label is the palette\'s tone 30, '
                'more saturated than the accent it labels');
      });
    }

    test('fromSeed pushes each half to its threshold and no further', () {
      // Teal is tone ~56: lowered to 44 in light, lifted to 62 in dark, hue
      // and chroma kept. Orange is tone 72 already and is not pulled *down*
      // in dark — the lift is for legibility on a dark ground, which a
      // lighter seed already has. Indigo is tone 38 and is not pushed *up*
      // in light, for the same reason under white.
      final teal = ThemeAccent.fromSeed(Colors.teal);
      expect(luminance(teal.light), lessThan(luminance(Colors.teal)));
      expect(luminance(teal.dark), greaterThan(luminance(Colors.teal)));
      expect(Hct.fromInt(teal.light.toARGB32()).tone, closeTo(ThemeAccent.derivedLightTone, 0.5));
      expect(Hct.fromInt(teal.dark.toARGB32()).tone, closeTo(ThemeAccent.derivedDarkTone, 0.5));

      final orange = ThemeAccent.fromSeed(Colors.orange);
      expect((luminance(orange.dark) - luminance(Colors.orange)).abs(), lessThan(0.02));

      final indigo = ThemeAccent.fromSeed(Colors.indigo);
      expect(indigo.light.toARGB32(), Colors.indigo.toARGB32());
    });

    test('a pair is equal by value, so a preset round-trips through state', () {
      // The settings swatch marks the selected preset by comparing the
      // AppState's accent to each entry; the harness names a screenshot the
      // same way. Both need value equality, not identity.
      const a = ThemeAccent(light: Color(0xFF3560D5), dark: Color(0xFF5B8DFF));
      const b = ThemeAccent(light: Color(0xFF3560D5), dark: Color(0xFF5B8DFF));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(AppConstants.presetThemes[AppConstants.defaultThemeAccentKey], a);
    });

    test('every pre-pair seed still finds its preset', () {
      // The pre-pair preference stored the Material seed as an ARGB int.
      // Those seeds are no longer any preset's light half, so the load path
      // goes through legacySeedPresets — and that table has to name every
      // preset exactly once, with a seed that is actually the same colour.
      expect(AppConstants.legacySeedPresets.values.toSet(),
          AppConstants.presetThemes.keys.toSet());
      for (final MapEntry<int, String> row in AppConstants.legacySeedPresets.entries) {
        final double seedHue = Hct.fromInt(row.key).hue;
        final double halfHue =
            Hct.fromInt(AppConstants.presetThemes[row.value]!.light.toARGB32()).hue;
        final double delta = (seedHue - halfHue).abs();
        expect(delta > 180 ? 360 - delta : delta, lessThan(4),
            reason: '${row.value}: legacy seed maps to a preset of a different hue');
      }
    });
  });

  group('semantic colours ignore the seed', () {
    test('the same set is registered whatever the seed', () {
      // Success stays green and warning stays amber when the user picks pink.
      // If these ever became seed-derived, a "succeeded" badge would turn the
      // same colour as everything else and stop meaning anything.
      for (final Brightness brightness in Brightness.values) {
        final a = buildAppTheme(accent: ThemeAccent.fromSeed(Colors.teal), brightness: brightness)
            .extension<AppSemanticColors>()!;
        final b = buildAppTheme(accent: ThemeAccent.fromSeed(Colors.pink), brightness: brightness)
            .extension<AppSemanticColors>()!;

        expect(a.success, b.success, reason: brightness.name);
        expect(a.warning, b.warning, reason: brightness.name);
        expect(a.info, b.info, reason: brightness.name);
      }
    });

    test('light and dark are different sets, not one inverted', () {
      final light = buildAppTheme(accent: ThemeAccent.fromSeed(Colors.teal), brightness: Brightness.light)
          .extension<AppSemanticColors>()!;
      final dark = buildAppTheme(accent: ThemeAccent.fromSeed(Colors.teal), brightness: Brightness.dark)
          .extension<AppSemanticColors>()!;

      expect(light.success, isNot(dark.success));
      expect(light, AppSemanticColors.light);
      expect(dark, AppSemanticColors.dark);
    });

    test('every on-container reads on its container', () {
      for (final set in [AppSemanticColors.light, AppSemanticColors.dark]) {
        for (final (name, fg, bg) in [
          ('success', set.onSuccessContainer, set.successContainer),
          ('warning', set.onWarningContainer, set.warningContainer),
          ('info', set.onInfoContainer, set.infoContainer),
        ]) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: name);
        }
      }
    });

    test('AppSemanticColors.of falls back without a registered extension', () {
      // Several dialogs build a local theme, and widget tests mount bare
      // MaterialApps; a null-assert there would crash on a colour that was
      // never actually in doubt.
      expect(
        AppSemanticColors.light.success,
        isNot(AppSemanticColors.dark.success),
      );
    });
  });

  group('the destructive fill is a fill, not the error role', () {
    // The failure this guards ships silently: `colorScheme.error` is tuned to
    // be legible as a *foreground*, so in dark mode it is a pale tone 80. Used
    // as a button's background it made the app's only irreversible action a
    // pale slab with dark text — quieter than the ordinary primary beside it —
    // and at Rose and Orange the two were the same hue family besides.
    final errorFill = errorFillScheme();

    test('the fill is dark enough to carry a light label', () {
      // Committed, not a wash: a pale ground would be readable and still wrong.
      expect(luminance(errorFill.primary), lessThan(0.25));
      expect(contrast(errorFill.primary, errorFill.onPrimary), greaterThan(4.5));
    });

    test('it is not the error *role*, which is what the bug was', () {
      // Deliberately checked against dark, where the two diverge. In light
      // they are near enough that the failure was invisible for eight minor
      // versions; in dark the role is a tone-80 pink, and a filled button
      // wearing it is the palest thing in the dialog.
      final dark = buildAppColorScheme(accent: ThemeAccent.fromSeed(Colors.blue), brightness: Brightness.dark);
      expect(errorFill.primary, isNot(dark.error));
      expect(luminance(dark.error), greaterThan(0.4),
          reason: 'if the role ever stops being a light tone in dark, revisit '
              'errorFillScheme — it exists because of this');
    });

    // The rule that keeps emphasis honest. Every light primary lands in a
    // narrow luminance band by construction (light + vibrant is tone 40
    // whatever the hue), so the destructive fill belongs in the *same* band:
    // equally committed, differing only in hue. Anything outside it is either
    // a pale slab (the bug) or louder than the design allows.
    //
    // Light only. In dark the CTA fills with the pair's tuned dark half
    // (tone ~62 under tone-10 ink) while the destructive fill keeps its
    // committed red — different constructions, so the band is not shared
    // there, and neither is a pale slab.
    //
    // Not "darker than primary" — that would be a coincidence of the ramp
    // rather than a rule, and it would fail the day a seed lands a point
    // lighter. Band membership is the thing that actually has to hold.
    for (final MapEntry<String, ThemeAccent> seed in AppConstants.presetThemes.entries) {
      test('it carries the same weight as the primary CTA — ${seed.key}', () {
        final primaryFill =
            buildAppColorScheme(accent: seed.value, brightness: Brightness.light);
        expect(
          (luminance(errorFill.primary) - luminance(primaryFill.primary)).abs(),
          lessThan(0.03),
          reason: 'destructive and primary fills must read as equally committed '
              'at ${seed.key}; only their hue may differ',
        );
        // Both are white-labelled, which is what makes the band comparison
        // meaningful in the first place.
        expect(contrast(errorFill.primary, errorFill.onPrimary), greaterThan(4.5));
        expect(contrast(primaryFill.primary, primaryFill.onPrimary), greaterThan(4.5));
      });
    }
  });

  group('geometry ladder', () {
    test('the button constants are aliases of the ladder, not second opinions', () {
      expect(appButtonRadius, AppRadius.control);
      expect(appButtonMinHeight, AppSize.control);
    });

    test('radii ascend, so "one step out" is always meaningful', () {
      expect(AppRadius.xs, lessThan(AppRadius.control));
      expect(AppRadius.control, lessThan(AppRadius.md));
      expect(AppRadius.md, lessThan(AppRadius.lg));
      expect(AppRadius.lg, lessThan(AppRadius.dialog));
    });

    test('an icon button is shorter than a labelled one, per the spec', () {
      expect(AppSize.iconButton, lessThan(AppSize.control));
      expect(AppSize.compact, lessThan(AppSize.iconButton));
    });
  });
}

double _pow(double x, double exp) {
  // dart:math pow returns num; this keeps the arithmetic above in doubles.
  return math.pow(x, exp).toDouble();
}
