// The workbench gallery's sort menu open across desktop, tablet, and phone
// widths, light and dark, plus Orange light accent to verify theme tokens.
//
//   flutter test test/screenshots/app_screens_workbench_sort_menu_test.dart

@Tags(<String>['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:material_ui/material_ui.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  for (final ShotSize size in kShotSizes) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('workbench · sortMenu @ ${size.label} ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: size,
          brightness: brightness,
          suffix: 'sortMenu',
          before: (_) async {
            AppState().setWorkbenchTab(0);
            AppState().isConsoleExpanded = false;
            AppState().clearImageSelection();
          },
          after: (WidgetTester tester) async {
            final sortIcon = find.byIcon(Icons.sort);
            if (sortIcon.evaluate().isNotEmpty) {
              await tester.tap(sortIcon);
            } else {
              await tester.tap(find.byIcon(Icons.more_vert));
              await settle(tester);
              await tester.tap(find.text('排序方式'));
            }
            await settle(tester);
          },
        );
      });
    }
  }

  testWidgets('workbench · sortMenu @ desktop light orange', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: kShotSizes.last,
      brightness: Brightness.light,
      accent: AppConstants.presetThemes['Orange'],
      suffix: 'sortMenu_orange',
      before: (_) async {
        AppState().setWorkbenchTab(0);
        AppState().isConsoleExpanded = false;
        AppState().clearImageSelection();
      },
      after: (WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.sort));
        await settle(tester);
      },
    );
  });
}
