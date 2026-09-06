import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

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

  ThemeData dark() => buildAppTheme(accent: ThemeAccent.fromSeed(seed), brightness: Brightness.dark);
  ThemeData light() => buildAppTheme(accent: ThemeAccent.fromSeed(seed), brightness: Brightness.light);

  test('filled buttons take the scheme\'s primary, whatever the brightness', () {
    // The CTA is no longer a special case. It used to fill from a separate
    // *light* scheme in both brightnesses, because Material's dark `primary`
    // is a tone-80 pastel meant to be read as a foreground and a button filled
    // with it was a lavender slab under dark text. The theme colour is a pair
    // now and dark `primary` is a hand-tuned fill, so the second scheme went.
    for (final theme in [dark(), light()]) {
      expect(resolve(theme, {})!, theme.colorScheme.primary);
      expect(styleOf(theme).foregroundColor?.resolve({}), theme.colorScheme.onPrimary);
      expect(styleOf(theme).shadowColor?.resolve({}), theme.colorScheme.primary,
          reason: 'the coloured lift must follow the fill it lifts');
    }
  });

  test('in dark the CTA wears the pair\'s dark half and its own ink', () {
    // The half of the pair that exists to be a fill. Before, dark took the
    // light half here, which left the CTA the only control in dark still
    // wearing the light accent, and the settings preview card — which draws
    // its dark-half button in dark `primary` — promising a button the app
    // never drew.
    final accent = ThemeAccent.fromSeed(seed);

    expect(resolve(dark(), {})!, accent.dark);
    expect(styleOf(dark()).foregroundColor?.resolve({}), accent.onDark);
  });

  test('in light the CTA wears the pair\'s light half under white', () {
    // The light half is a finished colour too, drawn verbatim — at a tone
    // white text is legible on, which the raw seed need not be (4.3:1 at the
    // spec's own `#4A72E8`). The CTA is the one place the accent carries
    // white at body size, so this is where that has to hold. Teal, not the
    // file's indigo: teal is tone ~56, so the half really is moved, and a
    // scheme that quietly drew the seed instead would fail here.
    final accent = ThemeAccent.fromSeed(Colors.teal);
    final theme = buildAppTheme(accent: accent, brightness: Brightness.light);

    expect(resolve(theme, {})!, accent.light);
    expect(resolve(theme, {})!, isNot(Colors.teal));
    expect(styleOf(theme).foregroundColor?.resolve({}), accent.onLight);
    expect(Hct.fromInt(theme.colorScheme.primary.toARGB32()).tone,
        closeTo(ThemeAccent.derivedLightTone, 0.5));
  });

  test('text buttons take the accent as text, not bare primary', () {
    // Material's default TextButton foreground is `primary`, which is a
    // fill tone. AppAccent.accentText is primary wherever primary reads on
    // the panel and canvas — seven presets — and the wash label where it
    // does not: Orange in light, where the label would otherwise be an
    // amber at 3.3:1.
    for (final preset in AppConstants.presetThemes.entries) {
      for (final brightness in Brightness.values) {
        final theme = buildAppTheme(accent: preset.value, brightness: brightness);
        expect(theme.textButtonTheme.style!.foregroundColor!.resolve({}), theme.colorScheme.accentText,
            reason: '${preset.key} ${brightness.name}');
      }
    }
    final orange = buildAppTheme(
        accent: AppConstants.presetThemes['Orange']!, brightness: Brightness.light);
    expect(orange.textButtonTheme.style!.foregroundColor!.resolve({}), isNot(orange.colorScheme.primary));
  });

  test('the FAB fills like the CTA it is', () {
    // Material's default FAB is primaryContainer / onPrimaryContainer — a
    // tone-90 pastel under tone-30 ink in light. The scheme makes those
    // roles safe, but the one button that opens the work on a phone should
    // carry the CTA's weight, not a lighter one.
    for (final theme in [dark(), light()]) {
      expect(theme.floatingActionButtonTheme.backgroundColor, theme.colorScheme.primary);
      expect(theme.floatingActionButtonTheme.foregroundColor, theme.colorScheme.onPrimary);
    }
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

  test('the phone bar marks selection the way the desktop rail does', () {
    // Material's own indicator is secondaryContainer — a hue-rotated,
    // low-chroma tone 90 that reads as grey-with-a-tint — which made the
    // bottom bar the one selected thing in the app not on the tint ladder.
    // Pinned to the shared AppAccent pair the rail and drawer read, not to
    // the roles behind it, so the three cannot drift apart.
    for (final theme in [dark(), light()]) {
      final bar = theme.navigationBarTheme;
      final scheme = theme.colorScheme;
      const selected = {WidgetState.selected};
      expect(bar.indicatorColor, scheme.navBackground(selected: true));
      expect(bar.iconTheme!.resolve(selected)!.color, scheme.navForeground(selected: true));
      expect(bar.labelTextStyle!.resolve(selected)!.color, scheme.navForeground(selected: true));
      expect(bar.iconTheme!.resolve({})!.color, scheme.navForeground(selected: false));
      // Naming a colour replaces Material's whole state machine; the
      // disabled tone has to survive that.
      expect(bar.iconTheme!.resolve({WidgetState.disabled})!.color,
          scheme.onSurface.withValues(alpha: AppAlpha.disabled));
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
  ThemeData light() => buildAppTheme(accent: ThemeAccent.fromSeed(seed), brightness: Brightness.light);

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
    expect(rendered.color, light().colorScheme.onPrimary);
    expect(rendered.fontSize, light().textTheme.bodySmall?.fontSize);
  });
}
