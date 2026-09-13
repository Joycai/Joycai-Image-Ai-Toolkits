// The file browser's staging column opens and closes on its own with the
// list — `B1b`: it costs 320px of grid, so it is only on screen while there
// is something in it or the user asked for it.
//
// Mounts the real app tree through the screenshot harness because the
// open/close decision lives in the screen's layout build, not in a state
// class, and a test against a different mount would prove nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/screens/browser/widgets/browser_staging_panel.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  testWidgets(
    'the staging column opens with the first staged file and closes when '
    'the list is emptied',
    (WidgetTester tester) async {
      await mountApp(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: const Size(1440, 900),
        label: 'staging-column-auto',
      );

      final browser = AppState().fileBrowserState;
      final staging = AppState().fileStagingState;

      // Every mutation persists through sqflite, whose lock arms a 10s
      // timeout: started under the fake clock it outlives the test. Run the
      // whole chain on the real loop, then pump the rebuild it left behind.
      Future<void> mutate(void Function() change) async {
        await tester.runAsync(() async {
          change();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();
      }

      expect(browser.filteredFiles, isNotEmpty,
          reason: 'the fixture browser must list files to stage');
      expect(staging.isEmpty, isTrue);
      expect(find.byType(BrowserStagingPanel), findsNothing,
          reason: 'nothing staged — the grid keeps the full width');

      await mutate(() => staging.add(browser.filteredFiles.first));
      expect(find.byType(BrowserStagingPanel), findsOneWidget,
          reason: 'the column earns its width the moment something is in it');

      await mutate(staging.clear);
      expect(find.byType(BrowserStagingPanel), findsNothing,
          reason: 'what opened on its own closes on its own once emptied');

      // And the cycle repeats: the next staged file opens it again.
      await mutate(() => staging.add(browser.filteredFiles.first));
      expect(find.byType(BrowserStagingPanel), findsOneWidget);

      await mutate(staging.clear);
    },
  );
}
