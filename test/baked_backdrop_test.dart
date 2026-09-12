// The window ground is drawn at a quarter of the window's resolution and
// upscaled. That is only allowed because the recipe is three very wide, very
// faint gradients over a flat fill — there is no edge in it to soften. This
// test is what says so: it paints the recipe at full resolution and at a
// quarter, upscales the small one the way the widget does, and compares every
// pixel.
//
// It guards the assumption, not the pixels: if someone adds a hard edge, a
// pattern or a tighter gradient to `AuroraRecipe`, the bake stops being
// invisible and this goes red before anyone ships a blurry wall.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/widgets/baked_backdrop.dart';

Future<ui.Image> _record(
  void Function(Canvas canvas, Size size) paint,
  Size size,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder), size);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    size.width.round(),
    size.height.round(),
  );
  picture.dispose();
  return image;
}

/// The small bake, blown up to [full] the way `RawImage(fit: BoxFit.fill)`
/// does it.
Future<ui.Image> _upscaled(ui.Image small, Size full) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    small,
    Rect.fromLTWH(0, 0, small.width.toDouble(), small.height.toDouble()),
    Offset.zero & full,
    Paint()..filterQuality = FilterQuality.medium,
  );
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    full.width.round(),
    full.height.round(),
  );
  picture.dispose();
  return image;
}

Future<Uint8List> _bytes(ui.Image image) async {
  final ByteData? data = await image.toByteData();
  return data!.buffer.asUint8List();
}

void main() {
  // A window-shaped box, at the 4K target's aspect ratio and a quarter of its
  // pixels so the test stays cheap. What matters is the 4x bake ratio, which
  // is the same at any size.
  const Size size = Size(960, 516);

  for (final Brightness brightness in Brightness.values) {
    test('the baked ground matches the live recipe (${brightness.name})', () async {
      final ColorScheme scheme = buildAppTheme(
        accent: AppConstants.presetThemes[AppConstants.defaultThemeAccentKey]!,
        brightness: brightness,
      ).colorScheme;
      final AuroraRecipe recipe = AuroraRecipe.of(scheme);

      final ui.Image live = await _record(recipe.paint, size);
      final ui.Image small = await _record(
        recipe.paint,
        Size((size.width / 4).ceilToDouble(), (size.height / 4).ceilToDouble()),
      );
      final ui.Image baked = await _upscaled(small, size);

      final Uint8List a = await _bytes(live);
      final Uint8List b = await _bytes(baked);
      expect(a.length, b.length);

      int worst = 0;
      int sum = 0;
      for (int i = 0; i < a.length; i++) {
        final int d = (a[i] - b[i]).abs();
        if (d > worst) worst = d;
        sum += d;
      }
      final double mean = sum / a.length;

      // Both figures, because they fail differently: `worst` catches a hard
      // edge that only exists in a few pixels, `mean` catches a recipe whose
      // whole surface has drifted.
      expect(worst, lessThanOrEqualTo(4),
          reason: 'a quarter-resolution bake is only invisible while the '
              'recipe has no edge in it — worst channel delta was $worst');
      expect(mean, lessThan(0.5), reason: 'mean channel delta was $mean');

      live.dispose();
      small.dispose();
      baked.dispose();
    });
  }
}
