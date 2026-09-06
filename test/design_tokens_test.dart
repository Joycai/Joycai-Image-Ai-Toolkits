import 'dart:io';
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

  Hct hct(Color c) => Hct.fromInt(c.toARGB32());

  /// Hue distance in HCT degrees, where "same hue" means the same thing at
  /// every chroma (HSV hue drifts with saturation for the blues and purples).
  double hueDistance(Color a, Color b) {
    final double d = (hct(a).hue - hct(b).hue).abs();
    return d > 180 ? 360 - d : d;
  }

  /// What Material's vibrant palette would draw as `primary` for [seed] —
  /// the thing the pair exists to replace.
  Color materialPrimary(Color seed, Brightness brightness) => ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
      ).primary;

  /// [ink] as text on each of [grounds], at AA or the given [floor].
  void expectReadsOn(
    Color ink,
    Iterable<(String, Color)> grounds, {
    required String preset,
    required String hint,
    double floor = 4.5,
  }) {
    for (final (name, ground) in grounds) {
      final double ratio = contrast(ink, ground);
      expect(ratio, greaterThanOrEqualTo(floor),
          reason: '$preset on $name: ${ratio.toStringAsFixed(2)}:1 — $hint');
    }
  }

  /// The Material seed each preset is named after and was tuned from. Design
  /// provenance for the tests below; the app itself no longer stores or
  /// reads these (the v40 migration rewrote the one row that did).
  const Map<String, Color> seedOf = {
    'Blue': Color(0xFF4A72E8),
    'BlueGrey': Colors.blueGrey,
    'Indigo': Colors.indigo,
    'Teal': Colors.teal,
    'Green': Colors.green,
    'Orange': Colors.orange,
    'DeepPurple': Colors.deepPurple,
    'Rose': Colors.pink,
  };

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
        // Up to the card, not `surfaceContainerHighest`: that one is the
        // track under a control, never a ground text is set on.
        expectReadsOn(
          dark.primary,
          [
            ('surface', dark.surface),
            ('surfaceContainerLow', dark.surfaceContainerLow),
            ('surfaceContainer', dark.surfaceContainer),
            ('surfaceContainerHigh', dark.surfaceContainerHigh),
          ],
          preset: preset.key,
          hint: 'the dark half was tuned too dark',
        );
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
        expect(hueDistance(light.primary, dark.primary), lessThan(30),
            reason: '${preset.key}: light and dark halves are different hues');
      });

      final light = buildAppColorScheme(accent: accent, brightness: Brightness.light);

      test('light primary is the tuned light half, verbatim, under white — ${preset.key}', () {
        // The light half was a seed once, and light primary was Material's
        // tone 40 of it — the *vibrant* palette's tone 40, at maximum chroma,
        // which turned indigo into `#1242FF` and deep purple into `#7801FF`.
        // Now it is drawn as-is, like the dark half.
        expect(light.primary, accent.light);
        expect(light.onPrimary, accent.onLight);
      });

      test('the light accent is the picked colour, not the palette\'s neon of it — ${preset.key}', () {
        // Measured against the seed the preset is named after: same hue, and
        // the seed's own chroma rather than whatever the gamut allows at that
        // tone. Hue in HCT, where "same" means the same thing at every chroma.
        final Color seed = seedOf[preset.key]!;
        expect(hueDistance(seed, accent.light), lessThan(4),
            reason: '${preset.key}: the light half is a different hue from its seed');
        expect(hct(accent.light).chroma, lessThanOrEqualTo(hct(seed).chroma + 2),
            reason: '${preset.key}: the light half is more saturated than the '
                'seed — that is the palette\'s tone 40 creeping back');
        expect(light.primary, isNot(materialPrimary(seed, Brightness.light)),
            reason: '${preset.key}: light primary is the palette\'s tone 40 again');
      });

      test('the light accent carries its ink, and the accent reads on every light ground — ${preset.key}', () {
        // Three different jobs, three different floors:
        //  · the CTA's ink on the CTA — AA, whichever ink onLight chose;
        //  · the accent *as text* (accentText) on every light ground, from
        //    white down to `surfaceDim` — AA;
        //  · the accent as an outline or icon (`primary`) on the grounds an
        //    outline sits on — the 3:1 non-text floor.
        // Where the ink is white (every preset but Orange) the margins
        // ThemeAccent.derivedLightTone is justified by are asserted too, so
        // the doc cannot outrun the code: tone 44 measures 5.5 under white
        // and 4.8 on the canvas; 47 is where the canvas drops under AA.
        const double whiteMargin = 5.5;
        const double canvasMargin = 4.8;
        final List<(String, Color)> textGrounds = [
          ('surfaceContainerLowest', light.surfaceContainerLowest),
          ('surface', light.surface),
          ('surfaceContainerLow', light.surfaceContainerLow),
          ('surfaceContainer', light.surfaceContainer),
          ('surfaceDim', light.surfaceDim),
        ];
        expect(contrast(light.onPrimary, light.primary), greaterThanOrEqualTo(4.5),
            reason: '${preset.key}: the CTA ink does not read on the light half');
        if (light.onPrimary.toARGB32() == Colors.white.toARGB32()) {
          expect(contrast(light.onPrimary, light.primary), greaterThanOrEqualTo(whiteMargin),
              reason: '${preset.key}: the light half is too light for white text');
          expectReadsOn(
            light.primary,
            [('surfaceContainer (the canvas)', light.surfaceContainer)],
            preset: preset.key,
            hint: 'the light half lost the canvas margin derivedLightTone promises',
            floor: canvasMargin,
          );
        }
        expectReadsOn(light.accentText, textGrounds,
            preset: preset.key, hint: 'the accent as text fails AA');
        expectReadsOn(
          light.primary,
          textGrounds.where((g) => g.$1 != 'surfaceDim'),
          preset: preset.key,
          hint: 'the accent as an outline or icon is under the 3:1 non-text floor',
          floor: 3.0,
        );
      });

      test('accentText is primary where primary reads, else the wash label — ${preset.key}', () {
        // The role that lets a hue leave tone 44. Decided from the scheme,
        // so it is one rule for presets and custom colours alike.
        final bool primaryReads = contrast(light.primary, light.surfaceContainer) >= 4.5 &&
            contrast(light.primary, light.surface) >= 4.5;
        expect(light.accentText, primaryReads ? light.primary : light.onAccentTint,
            reason: '${preset.key}: accentText picked the wrong side of 4.5:1');
        // Dark primary is tuned to read as text (the test above pins ≥ 4.5
        // on every dark ground), so dark accentText is always primary.
        expect(dark.accentText, dark.primary, reason: '${preset.key}: dark accentText left primary');
      });

      test('the light overlay and container roles are the accent\'s own chroma too — ${preset.key}', () {
        // `primaryFixedDim` is what a toast's action label reads
        // (AppAccent.accentOnOverlay). Left to the palette it is tone 80 at
        // maximum chroma: on a slate BlueGrey theme, a cyan "undo". The
        // container pair is not read by app code, but Material's own
        // defaults read it, so it is made safe rather than trusted absent.
        expect(light.primaryFixedDim, accent.lightTone(80));
        expect(light.primaryContainer, accent.lightTone(90));
        expect(light.onPrimaryContainer, accent.lightOnTint);
        expect(dark.primaryContainer, accent.darkTone(30));
        expect(dark.onPrimaryContainer, accent.darkTone(90));
        // Against the half each role is grown from: BlueGrey's dark half
        // deliberately carries more chroma than its seed.
        for (final (name, role, half) in [
          ('light primaryFixedDim', light.primaryFixedDim, accent.light),
          ('light primaryContainer', light.primaryContainer, accent.light),
          ('dark onPrimaryContainer', dark.onPrimaryContainer, accent.dark),
        ]) {
          expect(hct(role).chroma, lessThanOrEqualTo(hct(half).chroma + 2),
              reason: '${preset.key} $name: the palette\'s maximum-chroma tone is back');
        }
      });

      test('the light wash label is tone 30 at the light half\'s own chroma — ${preset.key}', () {
        expect(light.onPrimaryFixedVariant, accent.lightOnTint);
        expect(hct(light.onAccentTint).chroma, lessThanOrEqualTo(hct(accent.light).chroma + 2),
            reason: '${preset.key}: the wash label is the palette\'s tone 30, '
                'more saturated than the accent it labels');
      });
    }

    test('fromSeed sets the light half to its tone and lifts the dark one to its floor', () {
      // Teal is tone ~56: set to 44 in light, lifted to 62 in dark, hue and
      // chroma kept. Orange is tone 72 already and is not pulled *down* in
      // dark — the lift is for legibility on a dark ground, which a lighter
      // seed already has. Indigo is tone 38 and *is* lifted to 44 in light:
      // the light tone is a target, so the presets sit at one weight.
      final teal = ThemeAccent.fromSeed(Colors.teal);
      expect(luminance(teal.light), lessThan(luminance(Colors.teal)));
      expect(luminance(teal.dark), greaterThan(luminance(Colors.teal)));
      expect(hct(teal.light).tone, closeTo(ThemeAccent.derivedLightTone, 0.5));
      expect(hct(teal.dark).tone, closeTo(ThemeAccent.derivedDarkTone, 0.5));

      final orange = ThemeAccent.fromSeed(Colors.orange);
      expect((luminance(orange.dark) - luminance(Colors.orange)).abs(), lessThan(0.02));

      final indigo = ThemeAccent.fromSeed(Colors.indigo);
      expect(hct(indigo.light).tone, closeTo(ThemeAccent.derivedLightTone, 0.5));
    });

    test('a preset\'s light half is exactly what fromSeed makes of its seed', () {
      // The rule the presets follow and the rule fromSeed encodes are meant
      // to be one rule; this is what keeps them from drifting apart. (Dark
      // halves are hand-adjusted from fromSeed's floor and are not pinned.)
      // Orange is the one documented exception — see the test below.
      for (final MapEntry<String, Color> entry in seedOf.entries) {
        if (entry.key == 'Orange') continue;
        expect(AppConstants.presetThemes[entry.key]!.light, ThemeAccent.fromSeed(entry.value).light,
            reason: '${entry.key}: the preset\'s light half is not fromSeed(seed).light');
      }
    });

    test('Orange is the hue that leaves tone 44, and the pair of rules that lets it', () {
      // At 44 orange is a brown; no tone that is orange carries white. The
      // preset sits at 55 under its own ink (onLight), and text in the
      // accent falls back to the wash label (accentText). Both are decided
      // from the colour, not from the preset name, so this pins the
      // outcome, not a special case.
      final ThemeAccent orange = AppConstants.presetThemes['Orange']!;
      final light = buildAppColorScheme(accent: orange, brightness: Brightness.light);
      expect(hct(orange.light).tone, closeTo(55, 0.5));
      expect(hueDistance(orange.light, seedOf['Orange']!), lessThan(4));
      expect(hct(orange.light).chroma, greaterThan(hct(const Color(0xFF985900)).chroma),
          reason: 'the point of leaving tone 44 is to get the chroma back');
      expect(light.onPrimary, orange.lightTone(10), reason: 'white on it is 3.8:1; the ink is its own tone 10');
      expect(light.onPrimary.toARGB32(), isNot(Colors.white.toARGB32()));
      expect(light.accentText, light.onAccentTint, reason: 'as text, tone 55 is 3.3:1 on the canvas');
      expect(light.accentText, isNot(light.primary));
      // Every other preset keeps white ink and primary-as-text.
      for (final MapEntry<String, ThemeAccent> other in AppConstants.presetThemes.entries) {
        if (other.key == 'Orange') continue;
        final scheme = buildAppColorScheme(accent: other.value, brightness: Brightness.light);
        expect(scheme.onPrimary.toARGB32(), Colors.white.toARGB32(), reason: other.key);
        expect(scheme.accentText, scheme.primary, reason: other.key);
      }
    });

    test('a pair is equal by value, so a preset round-trips through state', () {
      // The settings swatch marks the selected preset by comparing the
      // AppState's accent to each entry; the harness names a screenshot the
      // same way. Both need value equality, not identity — so a fresh
      // instance with the same two values has to equal the constant.
      final ThemeAccent a = AppConstants.presetThemes[AppConstants.defaultThemeAccentKey]!;
      final ThemeAccent b = ThemeAccent(
        light: Color(a.light.toARGB32()),
        dark: Color(a.dark.toARGB32()),
      );
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the seed table names every preset, and each keeps its seed\'s hue', () {
      // The provenance table above is only as good as its coverage.
      expect(seedOf.keys.toSet(), AppConstants.presetThemes.keys.toSet());
      for (final MapEntry<String, Color> entry in seedOf.entries) {
        expect(hueDistance(entry.value, AppConstants.presetThemes[entry.key]!.light), lessThan(4),
            reason: '${entry.key}: named after a seed of a different hue');
      }
    });
  });

  group('the container roles stay out of the UI', () {
    test('no widget reads primaryContainer, onPrimaryContainer or inversePrimary', () {
      // Those roles are the vibrant palette's tones 90 / 30 / 40 at maximum
      // chroma — at the teal and green presets, `#00FDE7` and `#70FF77`. Set
      // beside a `primary` at the accent's own chroma they are a different
      // colour, not a paler one. Every tinted surface in the app is the
      // AppAccent ladder instead (accentTint / onAccentTint / accentRing),
      // and this is the greppable rule that keeps it so. `app_theme.dart` is
      // exempt because it is where the scheme is built.
      final RegExp role = RegExp(r'\b(onPrimaryContainer|primaryContainer|inversePrimary)\b');
      // The ladder spelled out by hand, which is the same bug one step
      // quieter: `primary.withValues(alpha: AppAlpha.tint)` is accentTint
      // with a second name, and a hand-picked 0.14 is a fourth wash.
      final RegExp handRolledWash = RegExp(
          r'primary\.(withValues\(alpha: (AppAlpha\.(tint|ring)|0\.1[0-9]|0\.28|0\.3[0-9])\)|withAlpha\((2[0-9]|3[0-9]|4[0-9]|8[0-9])\))');
      // A line comment starts at `//` after whitespace or at the line start;
      // a bare `split('//')` would also cut at the `//` in a URL literal and
      // hide whatever followed it.
      final RegExp lineComment = RegExp(r'(^|\s)//.*$');
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String path = entity.path.replaceAll(r'\', '/');
        // Exempt: where the scheme is built, and where the ladder is defined.
        if (path.endsWith('lib/core/app_theme.dart') || path.endsWith('lib/core/design_tokens.dart')) continue;
        // Generated localisations: a fifth of lib/ by line, and no colour in it.
        if (path.contains('/lib/l10n/') || path.startsWith('lib/l10n/')) continue;
        final List<String> lines = entity.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String code = lines[i].replaceFirst(lineComment, '');
          if (role.hasMatch(code) || handRolledWash.hasMatch(code)) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a container role or a hand-rolled wash reached the UI; use the AppAccent ladder');
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

    // The rule that keeps emphasis honest. Every light primary sits at
    // ThemeAccent.derivedLightTone (44) and the destructive fill is Material's
    // tone 40 of its red, so the two are within a few tones of each other:
    // equally committed, differing only in hue. Stated in tone — which is
    // L*, so the same yardstick at every hue — with the width spelled out,
    // rather than as a luminance band that a four-tone gap passes by 0.004.
    //
    // Light only. In dark the CTA fills with the pair's tuned dark half
    // (tone ~62 under tone-10 ink) while the destructive fill keeps its
    // committed red — different constructions, so the band is not shared
    // there, and neither is a pale slab.
    //
    // Not "darker than primary" — that would be a coincidence of the ramp
    // rather than a rule, and it would fail the day a seed lands a point
    // lighter. Band membership is the thing that actually has to hold.
    const double toneWidth = 5;
    for (final MapEntry<String, ThemeAccent> seed in AppConstants.presetThemes.entries) {
      test('it carries the same weight as the primary CTA — ${seed.key}', () {
        final primaryFill =
            buildAppColorScheme(accent: seed.value, brightness: Brightness.light);
        if (primaryFill.onPrimary.toARGB32() != Colors.white.toARGB32()) {
          // A fill under its own dark ink (Orange, tone 55) is a different
          // construction from a white-labelled one and sits above the band
          // by design; what has to hold is that it is still a committed fill
          // carrying its ink at AA, not a wash.
          expect(contrast(primaryFill.primary, primaryFill.onPrimary), greaterThanOrEqualTo(4.5),
              reason: '${seed.key}: a dark-ink CTA that does not carry its ink');
          expect(luminance(primaryFill.primary), lessThan(0.25),
              reason: '${seed.key}: the CTA has become a pale slab');
          return;
        }
        expect(
          (hct(errorFill.primary).tone - hct(primaryFill.primary).tone).abs(),
          lessThanOrEqualTo(toneWidth),
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
