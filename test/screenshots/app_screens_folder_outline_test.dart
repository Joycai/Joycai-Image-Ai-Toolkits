// Screenshots of the folder outline (`A1b`): the gallery and the file
// browser with three folders listed, so the bar under the toolbar / filter
// row is on film — desktop and phone, light and dark.
//
//   flutter test test/screenshots/app_screens_folder_outline_test.dart

@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:path/path.dart' as p;

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  // Two more folders beside the fixture's, with a few pictures each,
  // registered with both states here — in real async, after the suite's own
  // setUpAll has the singleton loaded. Awaiting the database from a shot's
  // `before` hook would deadlock: that runs in the test's fake zone.
  setUpAll(() async {
    final Directory root = env.sourceDir.parent;
    final List<String> extra = <String>[];
    for (final (String name, int n) in <(String, int)>[('outline_b', 4), ('outline_a', 2)]) {
      final Directory dir = Directory(p.join(root.path, name))..createSync(recursive: true);
      for (int i = 0; i < n; i++) {
        final img.Image image = img.Image(width: 480, height: 320 + i * 80);
        img.fill(image, color: img.ColorRgb8(60 + i * 40, 90, 140));
        await File(p.join(dir.path, '${name}_$i.png')).writeAsBytes(img.encodePng(image));
      }
      extra.add(dir.path);
    }
    for (final String dir in extra) {
      await AppState().galleryState.addBaseDirectory(dir);
      await AppState().fileBrowserState.addBaseDirectory(dir);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  for (final Brightness brightness in Brightness.values) {
    for (final ShotSize size in <ShotSize>[kShotSizes.first, kShotSizes.last]) {
      testWidgets('workbench · folder outline @ ${size.label} ${brightness.name}',
          (WidgetTester tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: size,
          brightness: brightness,
          suffix: 'outline',
          before: (_) async {
            AppState().setWorkbenchTab(0);
            AppState().isConsoleExpanded = false;
          },
        );
      });
    }

    testWidgets('fileBrowser · folder outline @ desktop ${brightness.name}',
        (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'outline',
      );
    });
  }
}
