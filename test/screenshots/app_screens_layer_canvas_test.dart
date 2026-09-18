// The layer canvas (`A7`): a Seedream decomposition stacked back on its base,
// the 「魔法杖」 layer picked — desktop light Blue (7a), tablet dark (7c) and
// phone light Orange (7c) — plus the gallery card's layer badge (7b).
//
//   flutter test test/screenshots/app_screens_layer_canvas_test.dart

@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/models/image_layer.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/layers/layer_canvas_page.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/image_layer_repository.dart';
import 'package:path/path.dart' as p;

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  late ImageLayerSet set;

  /// Writes the decomposition beside the gallery's fixtures and records it.
  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      final dir = p.dirname(env.fixtureImagePaths.first);
      String write(String name, img.Image image) {
        final path = p.join(dir, name);
        File(path).writeAsBytesSync(img.encodePng(image));
        if (!env.fixtureImagePaths.contains(path)) env.fixtureImagePaths.add(path);
        return path;
      }

      // Base: a sky-to-stone gradient with the figure "removed".
      final base = img.Image(width: 912, height: 1168);
      for (var y = 0; y < 1168; y++) {
        final t = y / 1168;
        final c = img.ColorRgb8((207 - 22 * t).round(), (227 - 28 * t).round(),
            (247 - 33 * t).round());
        img.drawLine(base, x1: 0, y1: y, x2: 911, y2: y, color: c);
      }
      final figure = img.Image(width: 861, height: 1137, numChannels: 4);
      img.fillCircle(figure, x: 430, y: 240, radius: 170,
          color: img.ColorRgba8(243, 214, 196, 255));
      img.fillPolygon(figure, vertices: [
        img.Point(230, 480), img.Point(630, 480),
        img.Point(760, 1137), img.Point(100, 1137),
      ], color: img.ColorRgba8(229, 122, 176, 255));
      final wand = img.Image(width: 160, height: 500, numChannels: 4);
      img.fillRect(wand, x1: 70, y1: 80, x2: 90, y2: 500,
          color: img.ColorRgba8(141, 110, 99, 255));
      img.fillCircle(wand, x: 80, y: 60, radius: 50,
          color: img.ColorRgba8(255, 213, 79, 255));
      final title = img.Image(width: 440, height: 140, numChannels: 4);
      img.fillRect(title, x1: 10, y1: 30, x2: 430, y2: 110, radius: 24,
          color: img.ColorRgba8(255, 255, 255, 230));

      final layers = [
        ImageLayer(path: write('magic_girl_0.png', base), setId: 'shot', zIndex: 0),
        ImageLayer(
            path: write('magic_girl_1.png', figure), setId: 'shot', zIndex: 1,
            name: '魔法少女立绘主体', description: '一名穿着华丽服饰的魔法少女',
            box: const LayerBox(27, 0, 888, 1137)),
        ImageLayer(
            path: write('magic_girl_2.png', wand), setId: 'shot', zIndex: 2,
            name: '魔法杖', description: '顶端镶着星形宝石的木质法杖',
            box: const LayerBox(600, 200, 760, 700)),
        ImageLayer(
            path: write('magic_girl_3.png', title), setId: 'shot', zIndex: 3,
            name: '标题字', description: '画面底部的英文标题与星形装饰',
            box: const LayerBox(80, 960, 520, 1100)),
      ];
      final repo = ImageLayerRepository();
      for (final l in layers) {
        await repo.save(l);
      }
      set = ImageLayerSet('shot', layers);
    });
  }

  Future<void> openCanvas(WidgetTester tester) async {
    final BuildContext context = tester.element(find.byType(Scaffold).first);
    // ignore: unawaited_futures
    showLayerCanvas(context, set, set.layers[2].path);
    // The base's size and every layer decode are real IO.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() async {
        for (final l in set.layers) {
          await precacheImage(FileImage(File(l.path)), context);
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
    await settle(tester);
  }

  for (final (size, brightness, accent) in [
    (kShotSizes.last, Brightness.light, null),
    (kShotSizes[1], Brightness.dark, null),
    (kShotSizes.first, Brightness.light, AppConstants.presetThemes['Orange']),
  ]) {
    testWidgets('workbench · layerCanvas @ ${size.label} ${brightness.name}',
        (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: size,
        brightness: brightness,
        accent: accent,
        suffix: 'layerCanvas',
        before: seed,
        after: openCanvas,
      );
    });
  }

  testWidgets('workbench · layer badge on the gallery @ desktop',
      (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: kShotSizes.last,
      suffix: 'layerBadge',
      before: seed,
    );
  });
}
