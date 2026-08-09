import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';

/// Covers the type scale added to [buildAppTheme] so widgets can read
/// `textTheme.bodyMedium` etc. instead of a literal `TextStyle(fontSize: N)`.
///
/// The whole point of the scale is that a font or seed-colour change actually
/// reaches text built from it — these pin the two ways that could quietly
/// fail to hold.
void main() {
  const seed = Colors.indigo;

  test('switching fontFamily reaches every scale slot, not just the default', () {
    // ThemeData's own `fontFamily` param does not reliably propagate onto a
    // caller-supplied textTheme's slots — that's the whole reason the scale
    // applies it manually. If this regresses, a font switch would silently
    // miss anything styled from e.g. bodyMedium.
    final withFont = buildAppTheme(
      seedColor: seed,
      brightness: Brightness.light,
      fontFamily: 'NotoSansSC',
    ).textTheme;

    for (final style in [
      withFont.titleLarge,
      withFont.titleMedium,
      withFont.titleSmall,
      withFont.bodyMedium,
      withFont.bodySmall,
      withFont.labelLarge,
      withFont.labelMedium,
      withFont.labelSmall,
    ]) {
      expect(style?.fontFamily, 'NotoSansSC');
    }
  });

  test('a null fontFamily leaves Material\'s own default untouched', () {
    // buildAppTheme is called with fontFamily: null for the "system font"
    // choice — .apply() must be skipped entirely then, not called with a
    // null family (which would stamp every slot's family to null instead of
    // leaving Material's own default, e.g. Roboto, in place).
    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final defaultFamily = ThemeData(useMaterial3: true).textTheme.bodyMedium?.fontFamily;

    expect(theme.textTheme.bodyMedium?.fontFamily, defaultFamily);
  });

  test('the scale sizes match what the app actually renders at', () {
    // Pins the sizes call sites are expected to migrate onto, so a slot
    // can't silently drift away from the value every screen already uses.
    final textTheme = buildAppTheme(seedColor: seed, brightness: Brightness.light).textTheme;

    expect(textTheme.titleLarge?.fontSize, 18);
    expect(textTheme.titleMedium?.fontSize, 14);
    expect(textTheme.titleSmall?.fontSize, 13);
    expect(textTheme.bodyMedium?.fontSize, 13);
    expect(textTheme.bodySmall?.fontSize, 12);
    expect(textTheme.labelLarge?.fontSize, 13);
    expect(textTheme.labelMedium?.fontSize, 11.5);
    expect(textTheme.labelSmall?.fontSize, 10);
  });

  test('slots stay tied to the seed colour, only weight/size are opinionated', () {
    // The scale merges its overrides on top of Material's own colour-derived
    // default so text keeps tracking colorScheme — it must not have stamped a
    // flat colour of its own on top.
    final colorScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final theme = buildAppTheme(seedColor: seed, brightness: Brightness.light);
    final defaultTheme = ThemeData(useMaterial3: true, colorScheme: colorScheme);

    expect(theme.textTheme.bodyMedium?.color, defaultTheme.textTheme.bodyMedium?.color);
    expect(theme.textTheme.titleLarge?.color, defaultTheme.textTheme.titleLarge?.color);
  });

  test('the scale is identical across light and dark, only colour differs', () {
    // Switching theme mode must not also reflow text — only the palette
    // should move.
    final light = buildAppTheme(seedColor: seed, brightness: Brightness.light).textTheme;
    final dark = buildAppTheme(seedColor: seed, brightness: Brightness.dark).textTheme;

    expect(dark.bodyMedium?.fontSize, light.bodyMedium?.fontSize);
    expect(dark.bodyMedium?.fontWeight, light.bodyMedium?.fontWeight);
    expect(dark.bodyMedium?.color, isNot(light.bodyMedium?.color));
  });
}
