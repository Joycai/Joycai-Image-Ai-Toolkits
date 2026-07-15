import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';

/// Covers the app-wide button theme.
///
/// The theme names a background for every filled button, which is a blunt
/// instrument: it reaches variants and states that were never meant to take the
/// primary fill. These pin the three that would otherwise break quietly.
void main() {
  const seed = Colors.indigo;

  ButtonStyle styleOf(ThemeData theme) => theme.filledButtonTheme.style!;

  Color? resolve(ThemeData theme, Set<WidgetState> states) =>
      styleOf(theme).backgroundColor?.resolve(states);

  ThemeData dark() => buildAppTheme(seedColor: seed, brightness: Brightness.dark);
  ThemeData light() => buildAppTheme(seedColor: seed, brightness: Brightness.light);

  test('filled buttons take the vibrant fill, not the scheme primary', () {
    final scheme = buttonFillScheme(seed);

    for (final theme in [dark(), light()]) {
      final fill = resolve(theme, {})!;

      // The theme's own primary is the muted tone this exists to avoid — pale
      // in dark, chroma-capped in both.
      expect(fill, isNot(theme.colorScheme.primary));
      expect(fill, scheme.primary);
      expect(styleOf(theme).foregroundColor?.resolve({}), scheme.onPrimary);
    }
  });

  test('the fill is more colourful than the palette it replaces', () {
    // The whole point: tonalSpot caps chroma, so its primary is grey-ish at
    // every tone. If this ever stops holding, the button is back to dull.
    final vibrant = HSLColor.fromColor(buttonFillScheme(seed).primary);
    final tonal = HSLColor.fromColor(light().colorScheme.primary);

    expect(vibrant.saturation, greaterThan(tonal.saturation));
  });

  test('the label keeps a readable contrast against the fill', () {
    for (final theme in [dark(), light()]) {
      final fill = resolve(theme, {})!;
      final label = styleOf(theme).foregroundColor!.resolve({})!;
      final ratio = (fill.computeLuminance() > label.computeLuminance())
          ? (fill.computeLuminance() + 0.05) / (label.computeLuminance() + 0.05)
          : (label.computeLuminance() + 0.05) / (fill.computeLuminance() + 0.05);

      // WCAG AA for normal text. Material guarantees this for a primary /
      // onPrimary pair taken from one scheme; taking them from two would not.
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Fill $fill vs label $label in ${theme.brightness}');
    }
  });

  test('a disabled filled button still paints something', () {
    // Naming a background in a theme replaces the default's whole state
    // machine. Leave the disabled tones out and the property resolves to null,
    // which is not "the Material default" — it is transparent.
    for (final theme in [dark(), light()]) {
      final disabled = resolve(theme, {WidgetState.disabled});
      expect(disabled, isNotNull, reason: 'Disabled fill vanished in ${theme.brightness}');
      expect(disabled!.a, greaterThan(0));
    }
  });

  test('the corner stays a corner at the smallest a button gets', () {
    // A radius only reads as rounded relative to the height it is cut from. At
    // half the height it is a stadium; 12 on the ~30px these rendered at was
    // close enough to look like one. This is the ratio, not the shape object —
    // the shape object was right the whole time the buttons looked wrong.
    expect(appButtonRadius, lessThan(appButtonMinHeight / 3));
  });

  testWidgets('a filled button keeps its shape and height on desktop', (tester) async {
    // Compact is what desktop platforms default to, and it subtracts 8px from a
    // button's minimum height — shrinking it out from under the theme, which is
    // how these ended up capsule-shaped. The button style pins density so the
    // floor holds; this reproduces the ambush.
    //
    // The call site's own style is here too: styleFrom leaves unnamed
    // properties null precisely so the theme still wins, and that must hold.
    await tester.pumpWidget(
      MaterialApp(
        theme: dark().copyWith(visualDensity: VisualDensity.compact),
        home: Scaffold(
          body: Center(
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ),
      ),
    );

    // The Material, not the FilledButton: the button pads itself out to a 48px
    // tap target that is not painted, so its size says nothing about the shape
    // the user sees.
    final painted = find.descendant(of: find.byType(FilledButton), matching: find.byType(Material)).first;

    final material = tester.widget<Material>(painted);
    expect(material.shape, isA<RoundedRectangleBorder>());
    expect((material.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(appButtonRadius));

    expect(tester.getSize(painted).height, appButtonMinHeight,
        reason: 'A density default shrank the button below its floor');
  });

  test('tonal buttons keep their own colours despite the filled theme', () {
    // FilledButton.tonal reads the same FilledButtonTheme, and a theme's
    // background outranks the tonal variant's default — so every tonal button
    // has to pass this style back in to stay secondary.
    for (final theme in [dark(), light()]) {
      final scheme = theme.colorScheme;
      final tonal = tonalButtonStyle(scheme);

      expect(tonal.backgroundColor?.resolve({}), scheme.secondaryContainer);
      expect(tonal.foregroundColor?.resolve({}), scheme.onSecondaryContainer);
      expect(tonal.backgroundColor?.resolve({WidgetState.disabled}), isNotNull);
    }
  });
}
