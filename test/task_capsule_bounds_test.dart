import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/task_capsule_monitor.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

/// The floating task monitor parks near the bottom edge and opens *downward*.
///
/// Shot on the prompts screen, not the queue: `C1` settles the overlap between
/// this and the run console — the queue's own screen takes the console, and
/// the capsule stays off it.
///
/// Which means that for as long as it has existed, opening it there ran its
/// task rows and its 查看全部 straight off the bottom of the window — the half
/// of the component that is actually worth opening. It is invisible in the
/// collapsed shot and impossible to notice in code, so it is pinned here: open
/// it, and assert it is still inside the window.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);

    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
    // A running task, so the capsule has rows to open onto.
    markOneTaskRunning(appState);
  });

  tearDownAll(() => env.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('opened at the bottom edge, the capsule stays inside the window',
      (WidgetTester tester) async {
    const Size window = Size(1440, 900);
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.prompts,
      size: window,
      label: 'capsule-bounds',
    );

    final Finder capsule = find.byType(TaskCapsuleMonitor);
    expect(capsule, findsOneWidget);

    final Rect collapsed = tester.getRect(capsule);
    expect(collapsed.bottom, lessThanOrEqualTo(window.height),
        reason: 'collapsed capsule already overflows');

    await tester.tap(capsule);
    await settle(tester);

    final Rect opened = tester.getRect(capsule);
    // It really did open — otherwise the assertion below passes for the wrong
    // reason and this test protects nothing.
    expect(opened.height, greaterThan(collapsed.height),
        reason: 'the tap did not expand the capsule');
    expect(opened.bottom, lessThanOrEqualTo(window.height),
        reason: 'the opened capsule runs off the bottom of the window');
    expect(opened.top, greaterThanOrEqualTo(0));
  });

  testWidgets('closing it again returns it to where the user parked it',
      (WidgetTester tester) async {
    // Bottom-anchored, so its bottom edge must not move at all while its top
    // edge does — a capsule that crept across an open/close cycle would walk
    // itself up the screen.
    const Size window = Size(1440, 900);
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.prompts,
      size: window,
      label: 'capsule-restore',
    );

    final Finder capsule = find.byType(TaskCapsuleMonitor);
    final Rect parked = tester.getRect(capsule);

    await tester.tap(capsule);
    await settle(tester);
    final Rect opened = tester.getRect(capsule);
    expect(opened.top, lessThan(parked.top));
    expect(opened.bottom, closeTo(parked.bottom, 1));

    await tester.tap(capsule);
    await settle(tester);
    expect(tester.getRect(capsule).top, closeTo(parked.top, 1));
  });
}
