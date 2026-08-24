import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  test('filled buttons take the fill scheme, whatever the brightness', () {
    final scheme = buttonFillScheme(seed);

    for (final theme in [dark(), light()]) {
      expect(resolve(theme, {})!, scheme.primary);
      expect(styleOf(theme).foregroundColor?.resolve({}), scheme.onPrimary);
    }
  });

  test('the fill is a dark ground in dark mode, where primary is a pale one', () {
    // What [buttonFillScheme] is still for. It used to be for two things —
    // dark's pale primary, and `tonalSpot` capping chroma at every tone — and
    // the second is gone: the whole scheme is `vibrant` now, so in *light* the
    // fill and `colorScheme.primary` are legitimately the same colour and
    // asserting they differ would be pinning a workaround to its own scaffold.
    //
    // Dark is the half that remains. There `primary` is a pale tone 80 meant
    // to be read as a foreground, and a button filled with it is a lavender
    // slab under dark text — lighter than the ordinary controls beside it, on
    // the one element that should carry the most weight.
    final fill = HSLColor.fromColor(buttonFillScheme(seed).primary);
    final darkPrimary = HSLColor.fromColor(dark().colorScheme.primary);

    expect(fill.lightness, lessThan(darkPrimary.lightness));
    expect(resolve(dark(), {})!, isNot(dark().colorScheme.primary));
  });

  test('light mode no longer needs a second scheme for the fill', () {
    // The change this records: `buildAppColorScheme` is `vibrant` too, so the
    // accent a selected row wears and the accent the CTA is filled with are
    // finally the same colour. Before, the CTA was the only vivid thing in the
    // window and every other accent a step duller than it.
    expect(light().colorScheme.primary, buttonFillScheme(seed).primary);
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

  testWidgets('all three button types carry the app corner, not just the filled one', (tester) async {
    // The theme used to define filledButtonTheme alone, so AppButton's `text`
    // and `destructiveOutline` variants — built on TextButton and
    // OutlinedButton — silently kept Material 3's StadiumBorder. A toolbar row
    // of Reset / Overwrite / Save rendered as two pills beside a rounded
    // rectangle. Reaching for the shared component is not enough on its own;
    // the theme has to reach through it.
    await tester.pumpWidget(
      MaterialApp(
        theme: light(),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(onPressed: _noop, child: Text('Save')),
                OutlinedButton(onPressed: _noop, child: Text('Overwrite')),
                TextButton(onPressed: _noop, child: Text('Reset')),
              ],
            ),
          ),
        ),
      ),
    );

    for (final type in [FilledButton, OutlinedButton, TextButton]) {
      final painted = find
          .descendant(of: find.byType(type), matching: find.byType(Material))
          .first;
      final shape = tester.widget<Material>(painted).shape;

      expect(shape, isA<RoundedRectangleBorder>(), reason: '$type kept a stadium shape');
      expect((shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(appButtonRadius),
          reason: '$type does not use the app corner');
      expect(tester.getSize(painted).height, greaterThanOrEqualTo(appButtonMinHeight),
          reason: '$type sits below the shared height floor');
    }
  });

  group('metricsOnly', _metricsOnlyTests);

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

void _noop() {}

/// Covers [AppTextScaleMetrics.metricsOnly].
///
/// It exists to stop a specific invisible-text bug: a Material 3 TextTheme
/// slot arrives stamped with `onSurface`, and an explicit colour on a Text
/// beats the ambient DefaultTextStyle -- so handing a raw slot to a filled
/// button's label paints dark-on-dark, and to a chip's label freezes it on
/// the unselected colour.
void _metricsOnlyTests() {
  const seed = Colors.indigo;
  ThemeData light() => buildAppTheme(seedColor: seed, brightness: Brightness.light);

  test('a scale slot really does carry a colour', () {
    // The premise. If Material ever stops stamping one, metricsOnly is dead
    // weight and this test says so.
    for (final slot in [
      light().textTheme.bodySmall,
      light().textTheme.labelMedium,
      light().textTheme.titleMedium,
    ]) {
      expect(slot?.color, isNotNull);
    }
  });

  test('metricsOnly is marked inheriting, or the merge never happens', () {
    // The subtle half. Text only merges its style over the ambient
    // DefaultTextStyle when `inherit` is true; TextStyle.merge returns the
    // incoming style wholesale otherwise. Copy a slot's own `inherit` through
    // and the label comes out with no colour at all -- black on a filled
    // button, which is worse than the bug this getter exists to fix. Caught
    // by the end-to-end case below, not by reading the code.
    expect(light().textTheme.labelMedium!.metricsOnly.inherit, isTrue);
  });

  test('metricsOnly drops the colour and keeps everything else', () {
    final slot = light().textTheme.labelMedium!;
    final bare = slot.metricsOnly;

    expect(bare.color, isNull, reason: 'the colour survived, which is the whole bug');
    expect(bare.fontSize, slot.fontSize);
    expect(bare.fontWeight, slot.fontWeight);
    expect(bare.letterSpacing, slot.letterSpacing);
    expect(bare.height, slot.height);
    expect(bare.fontFamily, slot.fontFamily);
  });

  test('copyWith cannot do this, which is why the extension exists', () {
    // Documents the trap: null in copyWith means "leave it alone", so the
    // obvious spelling silently keeps the colour.
    final slot = light().textTheme.labelMedium!;

    expect(slot.copyWith(color: null).color, slot.color);
  });

  testWidgets('a metricsOnly label takes the colour of the widget above it', (tester) async {
    // The end to end claim: inside a filled button the label must come out
    // the button's foreground, not the scale's onSurface.
    await tester.pumpWidget(MaterialApp(
      theme: light(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () {},
              child: Text('Go', style: Theme.of(context).textTheme.bodySmall?.metricsOnly),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final rendered = tester
        .renderObject<RenderParagraph>(
          find.descendant(of: find.text('Go'), matching: find.byType(RichText)),
        )
        .text
        .style!;

    expect(rendered.color, isNot(light().colorScheme.onSurface));
    expect(rendered.color, buttonFillScheme(seed).onPrimary);
    expect(rendered.fontSize, light().textTheme.bodySmall?.fontSize);
  });
}
