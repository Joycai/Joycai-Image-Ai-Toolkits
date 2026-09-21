// What every app-screen shot file shares: the fixture setup and the
// screen × size matrix.
//
// The shots used to live in one file. `flutter test` spreads *files* across
// cores but runs a file's own tests one after another, so that single file
// set the wall time of a full local run on its own (~150s of a ~150s run).
// Split by area, the runner schedules the pieces like any other test files.
// Each file installs its own [FixtureEnv] — its own temp tree and database —
// so the pieces never contend for a lock when they run side by side.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'fixture_env.dart';
import 'fixture_seed.dart';
import 'shoot.dart';

/// Installs this file's fixture environment and hands it to [onReady] once
/// it is seeded and settled.
void setUpScreenSuite(void Function(FixtureEnv env) onReady) {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    // Order matters: the environment must exist before the first AppState()
    // touch, and the seed before loadSettings() reads it back.
    env = installFixtureEnv(binding);
    await seedFixtures(env);

    final AppState appState = AppState();
    await appState.loadSettings();
    // setUpAll runs in real async (no fake-async zone), which is the only place
    // the compute()-based gallery and file-browser scans actually complete.
    await Future<void>.delayed(const Duration(seconds: 1));
    markOneTaskRunning(appState);
    onReady(env);
  });

  tearDownAll(() => env.dispose());
}

/// Each of [screens] at every [kShotSizes] width in light, plus a dark shot at
/// desktop width.
void shootMatrix(FixtureEnv Function() env, List<AppScreen> screens) {
  for (final AppScreen screen in screens) {
    for (final ShotSize size in kShotSizes) {
      testWidgets('${screen.name} @ ${size.label}', (WidgetTester tester) async {
        await shoot(tester, env: env(), screen: screen, size: size);
      });
    }

    testWidgets('${screen.name} @ desktop dark', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env(),
        screen: screen,
        size: kShotSizes.last,
        brightness: Brightness.dark,
      );
    });
  }
}

/// Runs [action] in real async, *together with the frame it asks for*, then
/// settles.
///
/// For an action that reaches the database — a key that persists a setting, a
/// tab switch that mounts a panel which loads on mount. The frame is the part
/// that is easy to leave outside: the action only marks the tree dirty, and
/// it is the next pump that mounts the new panel and runs the post-frame
/// callback that starts its query. Pumped under fake async, that query's
/// sqflite lock watchdog is a ten-second *fake* timer which only a later pump
/// can cancel, and only once the real reply is in — so whether the test ends
/// with "A Timer is still pending" is down to how fast the runner's disk
/// answered. Started out here the query owns a real timer and finishes on its
/// own, however late; the wait below is for what it draws, not for safety.
Future<void> actInRealAsync(
  WidgetTester tester,
  Future<void> Function() action, [
  int frames = 6,
]) async {
  await tester.runAsync(() async {
    await action();
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
  });
  await settle(tester, frames);
}

/// Pumps [frames] 120ms frames — enough for a menu or a page push to land.
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}
