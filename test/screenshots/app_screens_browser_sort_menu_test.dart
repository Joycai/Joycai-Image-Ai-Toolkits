// The file browser's sort menu open (`B1a · 1f`): the glass float under the
// sort button, radios for field and direction, the grouping checkbox with
// its hint. Light and dark, desktop.
//
//   flutter test test/screenshots/app_screens_browser_sort_menu_test.dart

@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · sortMenu @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'sortMenu',
        after: (WidgetTester tester) async {
          await tester.tap(find.byIcon(Icons.sort));
          await settle(tester);
        },
      );
    });
  }
}
