import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';

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

  for (final brightness in Brightness.values) {
    test('every neutral role is a true grey in $brightness', () {
      // fromSeed alone tints all of these with the seed's hue. Any one of
      // them drifting off grey puts the accent hue back into the background,
      // which is what this exists to prevent.
      final scheme = buildAppColorScheme(seedColor: Colors.teal, brightness: brightness);

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
        expect(chromaOf(color), lessThan(0.01), reason: '$name carries the seed hue in $brightness');
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

  test('the theme hands the neutralised scheme to widgets, not the raw seeded one', () {
    // buildAppTheme could easily go on passing ColorScheme.fromSeed straight
    // through; then every widget reading Theme.of(context).colorScheme would
    // still get tinted greys and none of the above would matter.
    final theme = buildAppTheme(seedColor: Colors.teal, brightness: Brightness.light);
    final expected = buildAppColorScheme(seedColor: Colors.teal, brightness: Brightness.light);

    expect(theme.colorScheme.surfaceContainerHighest, expected.surfaceContainerHighest);
    expect(chromaOf(theme.colorScheme.surface), lessThan(0.01));
  });
}
