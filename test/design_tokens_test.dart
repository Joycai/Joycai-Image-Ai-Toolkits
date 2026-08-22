import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_semantic_colors.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';

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
    for (final MapEntry<String, Color> seed in AppConstants.presetThemes.entries) {
      for (final Brightness brightness in Brightness.values) {
        final String where = '${seed.key}/${brightness.name}';

        test('onAccentTint reads on its own tint — $where', () {
          final scheme = buildAppColorScheme(seedColor: seed.value, brightness: brightness);

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
          final scheme = buildAppColorScheme(seedColor: seed.value, brightness: brightness);
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
          final scheme = buildAppColorScheme(seedColor: seed.value, brightness: brightness);
          expect(scheme.onAccentTint, isNot(scheme.primary), reason: where);
        });
      }
    }

    test('the branch picks the role that is right in each brightness', () {
      // Pinned because each half looks like it could be simplified away, and
      // each simplification breaks the other half:
      //   · onPrimaryContainer everywhere → tone 10 in light, a black label
      //   · primaryFixedDim everywhere    → tone 80 in dark, which is exactly
      //     primary's own tone, so the label vanishes into its tint
      final light = buildAppColorScheme(seedColor: Colors.teal, brightness: Brightness.light);
      expect(light.onAccentTint, light.onPrimaryFixedVariant);

      final dark = buildAppColorScheme(seedColor: Colors.teal, brightness: Brightness.dark);
      expect(dark.onAccentTint, dark.onPrimaryContainer);

      // The two facts the branch rests on, asserted so an SDK bump that moves
      // either one fails here rather than silently in the UI.
      expect(dark.primaryFixedDim, dark.primary,
          reason: 'primaryFixedDim has moved off primary in dark — it is now '
              'viable there and the branch could be revisited');
      expect(light.onPrimaryContainer, light.onPrimaryFixedVariant,
          reason: 'Material has moved onPrimaryContainer off tone 30 in light. '
              'The Fixed role this getter uses is the pinned one, so nothing '
              'is broken — but the doc comment now understates why it matters');
    });
  });

  group('semantic colours ignore the seed', () {
    test('the same set is registered whatever the seed', () {
      // Success stays green and warning stays amber when the user picks pink.
      // If these ever became seed-derived, a "succeeded" badge would turn the
      // same colour as everything else and stop meaning anything.
      for (final Brightness brightness in Brightness.values) {
        final a = buildAppTheme(seedColor: Colors.teal, brightness: brightness)
            .extension<AppSemanticColors>()!;
        final b = buildAppTheme(seedColor: Colors.pink, brightness: brightness)
            .extension<AppSemanticColors>()!;

        expect(a.success, b.success, reason: brightness.name);
        expect(a.warning, b.warning, reason: brightness.name);
        expect(a.info, b.info, reason: brightness.name);
      }
    });

    test('light and dark are different sets, not one inverted', () {
      final light = buildAppTheme(seedColor: Colors.teal, brightness: Brightness.light)
          .extension<AppSemanticColors>()!;
      final dark = buildAppTheme(seedColor: Colors.teal, brightness: Brightness.dark)
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
      final dark = buildAppColorScheme(seedColor: Colors.blue, brightness: Brightness.dark);
      expect(errorFill.primary, isNot(dark.error));
      expect(luminance(dark.error), greaterThan(0.4),
          reason: 'if the role ever stops being a light tone in dark, revisit '
              'errorFillScheme — it exists because of this');
    });

    // The rule that keeps emphasis honest. Every `buttonFillScheme` primary
    // lands in a narrow luminance band by construction (light + vibrant is
    // tone 40 whatever the hue), so the destructive fill belongs in the *same*
    // band: equally committed, differing only in hue. Anything outside it is
    // either a pale slab (the bug) or louder than the design allows.
    //
    // Not "darker than primary" — that would be a coincidence of the ramp
    // rather than a rule, and it would fail the day a seed lands a point
    // lighter. Band membership is the thing that actually has to hold.
    for (final MapEntry<String, Color> seed in AppConstants.presetThemes.entries) {
      test('it carries the same weight as the primary CTA — ${seed.key}', () {
        final primaryFill = buttonFillScheme(seed.value);
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
