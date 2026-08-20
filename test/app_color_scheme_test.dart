import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';

/// Covers [buildAppColorScheme]'s split: accents from the seed, greys from
/// nobody.
///
/// The whole point is that changing the seed moves the accent roles and
/// nothing else — so a surface tuned against one seed still looks right at
/// the next, and the accent stays meaningful because it appears nowhere by
/// accident.
void main() {
  /// How far a colour is from grey. Zero means R, G and B are equal.
  double chromaOf(Color color) {
    final r = color.r, g = color.g, b = color.b;
    return [r, g, b].reduce((a, b) => a > b ? a : b) - [r, g, b].reduce((a, b) => a < b ? a : b);
  }

  /// The colour's hue in degrees, 0–360. Meaningless at zero chroma, so only
  /// ask for it after checking [chromaOf].
  double hueOf(Color color) => HSVColor.fromColor(color).hue;

  for (final brightness in Brightness.values) {
    test('every neutral role carries the design’s blue, never the seed’s hue in $brightness', () {
      // Before the restyle this asserted zero chroma: fromSeed tints all of
      // these with the seed's hue, and any one of them drifting off grey put
      // the accent hue back into the background.
      //
      // The ramp is no longer neutral — the spec's canvas is #ECEFF8 and its
      // body text #171C3B, both cool by design — so "is it grey" can't be the
      // question any more. The question that survives is *whose* tint it is.
      // Seeded here with orange, the hue furthest from the ramp's own: every
      // neutral must still come out blue. One drifting toward the seed is the
      // same regression the zero-chroma assertion used to catch.
      final scheme = buildAppColorScheme(seedColor: Colors.orange, brightness: brightness);

      final neutrals = {
        'surface': scheme.surface,
        'surfaceDim': scheme.surfaceDim,
        'surfaceBright': scheme.surfaceBright,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'onSurface': scheme.onSurface,
        'onSurfaceVariant': scheme.onSurfaceVariant,
        'outline': scheme.outline,
        'outlineVariant': scheme.outlineVariant,
        'inverseSurface': scheme.inverseSurface,
        'onInverseSurface': scheme.onInverseSurface,
        'surfaceTint': scheme.surfaceTint,
      };

      neutrals.forEach((name, color) {
        // White and near-white have no meaningful hue; nothing to check.
        if (chromaOf(color) < 0.01) return;
        expect(hueOf(color), inInclusiveRange(210, 245),
            reason: '$name is not the ramp’s blue in $brightness — '
                'it has drifted toward the seed');
      });
    });

    test('the greys do not move when the seed changes in $brightness', () {
      // The practical payoff: a panel tuned against one seed must not need
      // re-tuning at the next.
      final teal = buildAppColorScheme(seedColor: Colors.teal, brightness: brightness);
      final crimson = buildAppColorScheme(seedColor: Colors.red, brightness: brightness);

      expect(crimson.surface, teal.surface);
      expect(crimson.surfaceContainerHighest, teal.surfaceContainerHighest);
      expect(crimson.onSurface, teal.onSurface);
      expect(crimson.outlineVariant, teal.outlineVariant);
    });

    test('accent roles still follow the seed in $brightness', () {
      // The other half of the split — neutralising must not have flattened
      // the roles that carry the user's colour.
      final teal = buildAppColorScheme(seedColor: Colors.teal, brightness: brightness);
      final crimson = buildAppColorScheme(seedColor: Colors.red, brightness: brightness);

      expect(crimson.primary, isNot(teal.primary));
      expect(chromaOf(teal.primary), greaterThan(0.05));
      expect(chromaOf(teal.secondaryContainer), greaterThan(0.01));
      expect(chromaOf(teal.error), greaterThan(0.05));
    });

    test('body text still contrasts against the surface it sits on in $brightness', () {
      // onSurface and surface now come from a different scheme than the one
      // that paired them. Material's own guarantee only covers a matched
      // pair, so the pairing this function assembles has to be checked.
      final scheme = buildAppColorScheme(seedColor: Colors.teal, brightness: brightness);
      final surface = scheme.surface.computeLuminance();
      final onSurface = scheme.onSurface.computeLuminance();
      final ratio = surface > onSurface
          ? (surface + 0.05) / (onSurface + 0.05)
          : (onSurface + 0.05) / (surface + 0.05);

      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Body text is unreadable in $brightness');
    });
  }

  test('the ramp is one fixed table, not a per-seed derivation', () {
    // The invariant the restyle kept when it dropped zero-chroma. Every
    // neutral role — not just the four spot-checked above — has to be
    // identical across every seed the user can pick, or the cool tint stops
    // being the design's and starts being the seed's.
    for (final brightness in Brightness.values) {
      final reference = buildAppColorScheme(
        seedColor: AppConstants.presetThemes.values.first,
        brightness: brightness,
      );
      for (final seed in AppConstants.presetThemes.entries) {
        final scheme = buildAppColorScheme(seedColor: seed.value, brightness: brightness);
        expect(
          [
            scheme.surface,
            scheme.surfaceDim,
            scheme.surfaceBright,
            scheme.surfaceContainerLowest,
            scheme.surfaceContainerLow,
            scheme.surfaceContainer,
            scheme.surfaceContainerHigh,
            scheme.surfaceContainerHighest,
            scheme.onSurface,
            scheme.onSurfaceVariant,
            scheme.outline,
            scheme.outlineVariant,
            scheme.inverseSurface,
            scheme.onInverseSurface,
            scheme.surfaceTint,
          ],
          [
            reference.surface,
            reference.surfaceDim,
            reference.surfaceBright,
            reference.surfaceContainerLowest,
            reference.surfaceContainerLow,
            reference.surfaceContainer,
            reference.surfaceContainerHigh,
            reference.surfaceContainerHighest,
            reference.onSurface,
            reference.onSurfaceVariant,
            reference.outline,
            reference.outlineVariant,
            reference.inverseSurface,
            reference.onInverseSurface,
            reference.surfaceTint,
          ],
          reason: 'the ramp moved at seed ${seed.key} in $brightness',
        );
      }
    }
  });

  test('a panel reads as lifted off the canvas in both brightnesses', () {
    // The app's own role convention, which the dark ramp deliberately gives
    // the opposite ordering to Material's: surfaceContainer is the canvas a
    // screen paints, surface is a panel floating on it, and the panel is the
    // lighter of the two in *both* brightnesses. Material's dark scheme has
    // these the other way round, so nothing but this test holds it.
    for (final brightness in Brightness.values) {
      final scheme = buildAppColorScheme(seedColor: Colors.teal, brightness: brightness);
      expect(
        scheme.surface.computeLuminance(),
        greaterThan(scheme.surfaceContainer.computeLuminance()),
        reason: 'a panel is not lifted off the canvas in $brightness',
      );
    }
  });

  test('the theme hands the neutralised scheme to widgets, not the raw seeded one', () {
    // buildAppTheme could easily go on passing ColorScheme.fromSeed straight
    // through; then every widget reading Theme.of(context).colorScheme would
    // still get tinted greys and none of the above would matter.
    final theme = buildAppTheme(seedColor: Colors.teal, brightness: Brightness.light);
    final expected = buildAppColorScheme(seedColor: Colors.teal, brightness: Brightness.light);

    expect(theme.colorScheme.surfaceContainerHighest, expected.surfaceContainerHighest);
    expect(hueOf(theme.colorScheme.surface), inInclusiveRange(210, 245));
  });
}
