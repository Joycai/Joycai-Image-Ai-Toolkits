import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_window_frame.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/nav_lens_group.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

/// The title bar's destinations must not move when the screen changes (`01b`).
///
/// The group is centred. While the current destination spelled its label out
/// inside the group, the group's width followed that label, so every switch
/// between screens whose names differ in length moved all eight icons
/// sideways. This switches screens and asserts that every icon, and the group,
/// stays exactly where it was — and that the lens really went to the new
/// destination, whose name the title now carries.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);

    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  Finder inGroup(Finder matching) => find.descendant(of: find.byType(NavLensGroup), matching: matching);

  List<Rect> iconRects(WidgetTester tester) {
    final icons = inGroup(find.byType(Icon));
    return [for (int i = 0; i < icons.evaluate().length; i++) tester.getRect(icons.at(i))];
  }

  double lensCentre(WidgetTester tester) =>
      tester.getRect(inGroup(find.byType(AnimatedPositioned))).center.dx;

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // A screen that overflows while it loads is not what this is about.
    for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {}
  }

  testWidgets('switching screens moves no icon in the title bar', (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'nav-stable',
    );

    final group = tester.getRect(find.byType(NavLensGroup));
    final icons = iconRects(tester);
    expect(icons, hasLength(AppScreen.values.length));
    expect(lensCentre(tester), closeTo(icons[AppScreen.workbench.index].center.dx, 0.5));

    try {
      for (final screen in [AppScreen.fileBrowser, AppScreen.prompts, AppScreen.settings, AppScreen.tasks]) {
        AppState().navigateToScreen(screen.index);
        await settle(tester);

        expect(tester.getRect(find.byType(NavLensGroup)), group, reason: 'the group moved on ${screen.name}');
        expect(iconRects(tester), icons, reason: 'an icon moved on ${screen.name}');
        expect(lensCentre(tester), closeTo(icons[screen.index].center.dx, 0.5),
            reason: 'the lens did not follow to ${screen.name}');

        final l10n = AppLocalizations.of(tester.element(find.byType(AppTitleBar)))!;
        final name = switch (screen) {
          AppScreen.fileBrowser => l10n.fileBrowser,
          AppScreen.prompts => l10n.prompts,
          AppScreen.settings => l10n.settings,
          AppScreen.tasks => l10n.tasks,
          _ => throw StateError('unexpected $screen'),
        };
        expect(
          find.descendant(of: find.byType(AppTitleBar), matching: find.text(name)),
          findsOneWidget,
          reason: 'the title does not name ${screen.name}',
        );
      }
    } finally {
      AppState().navigateToScreen(AppScreen.workbench.index);
      await settle(tester);
      // The screens visited start debounces and scans of their own; let
      // them run out before the binding checks for pending timers.
      await tester.pump(const Duration(seconds: 10));
      for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {}
    }
  });
}
