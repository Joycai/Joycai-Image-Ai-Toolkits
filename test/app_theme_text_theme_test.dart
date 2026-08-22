import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';

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

    // 16 since the restyle — the spec's 页面标题 row. See _buildTextTheme.
    expect(textTheme.titleLarge?.fontSize, 16);
    expect(textTheme.titleMedium?.fontSize, 14);
    expect(textTheme.titleSmall?.fontSize, 13);
    expect(textTheme.bodyMedium?.fontSize, 13);
    expect(textTheme.bodySmall?.fontSize, 12);
    expect(textTheme.labelLarge?.fontSize, 13);
    expect(textTheme.labelMedium?.fontSize, 11.5);
    expect(textTheme.labelSmall?.fontSize, 10);
  });

  test('slots stay tied to the scheme, only weight/size are opinionated', () {
    // The scale merges its overrides on top of Material's own colour-derived
    // default so text keeps tracking colorScheme — it must not have stamped a
    // flat colour of its own on top.
    final colorScheme = buildAppColorScheme(seedColor: seed, brightness: Brightness.light);
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

  group('tracking follows the size, never the slot', () {
    // The rule Apple states and the app was breaking in three places: letter
    // spacing is a property of how big the letters are, not of which TextTheme
    // slot a caller happened to reach for. Before AppType.trackingFor, tracking
    // was left to Material — whose values are attached per slot and tuned to
    // Material's sizes, all of which this app moved.
    TextTheme scale() =>
        buildAppTheme(seedColor: seed, brightness: Brightness.light).textTheme;

    test('two slots at the same size are spaced the same', () {
      final t = scale();

      // 16px: titleLarge shipped 0.0 and bodyLarge 0.5 — the same letters at
      // the same size, half a pixel apart depending on the slot name.
      expect(t.titleLarge?.fontSize, t.bodyLarge?.fontSize);
      expect(t.titleLarge?.letterSpacing, t.bodyLarge?.letterSpacing);

      // 13px: titleSmall and labelLarge shipped 0.1, bodyMedium 0.25.
      expect(t.titleSmall?.fontSize, 13);
      expect(t.labelLarge?.fontSize, 13);
      expect(t.bodyMedium?.fontSize, 13);
      expect(t.titleSmall?.letterSpacing, t.labelLarge?.letterSpacing);
      expect(t.titleSmall?.letterSpacing, t.bodyMedium?.letterSpacing);
    });

    test('every slot carries a tracking, chosen rather than inherited', () {
      final t = scale();
      for (final (name, style) in [
        ('titleLarge', t.titleLarge), ('titleMedium', t.titleMedium),
        ('titleSmall', t.titleSmall), ('bodyLarge', t.bodyLarge),
        ('bodyMedium', t.bodyMedium), ('bodySmall', t.bodySmall),
        ('labelLarge', t.labelLarge), ('labelMedium', t.labelMedium),
        ('labelSmall', t.labelSmall),
      ]) {
        expect(style?.letterSpacing, isNotNull, reason: name);
        expect(style?.letterSpacing, AppType.trackingFor(style!.fontSize!),
            reason: name);
      }
    });

    test('the ladder opens up as the text gets smaller, and never reverses', () {
      // Monotonic, and running the right way: small text needs the air, large
      // text reads as loose if it keeps it. labelSmall (10px) and labelMedium
      // (11.5px) both shipped at 0.5 — flat exactly where it should be opening
      // fastest.
      const sizes = [10.0, 11.0, 11.5, 12.0, 13.0, 14.0, 15.0, 16.0];
      for (int i = 0; i < sizes.length - 1; i++) {
        expect(AppType.trackingFor(sizes[i]),
            greaterThan(AppType.trackingFor(sizes[i + 1])),
            reason: '${sizes[i]} vs ${sizes[i + 1]}');
      }

      // Flat outside the ladder rather than extrapolating into nonsense.
      expect(AppType.trackingFor(4), AppType.trackingFor(10));
      expect(AppType.trackingFor(64), AppType.trackingFor(16));
      expect(AppType.trackingFor(16), 0.0);
    });

    test('the tracked caption is off the ladder, deliberately', () {
      // AppSectionLabel opens a caps caption far past anything trackingFor
      // would hand back at its size. That is a separate decision about a
      // separate kind of text, and collapsing the two would either flatten the
      // caption or blow every label in the app apart.
      expect(AppType.trackedLabelSpacing,
          greaterThan(AppType.trackingFor(11.5) * 2));
    });
  });

  group('leading runs against size', () {
    test('the three prose steps are ordered, and display is tightest', () {
      expect(AppType.displayHeight, lessThan(AppType.tightHeight));
      expect(AppType.tightHeight, lessThan(AppType.proseHeight));
      expect(AppType.proseHeight, lessThan(AppType.looseHeight));
    });
  });
}
