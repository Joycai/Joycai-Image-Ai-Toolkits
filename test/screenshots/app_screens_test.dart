// Renders every screen of the real app to a PNG in build/ui-screenshots/.
//
//   flutter test test/screenshots
//   flutter test test/screenshots --plain-name workbench
//
// This is a debugging tool, not a regression gate: the comparator installed by
// flutter_test_config.dart always overwrites and always passes. See
// docs/ui-screenshot-harness.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';

void main() {
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
  });

  tearDownAll(() => env.dispose());

  for (final AppScreen screen in AppScreen.values) {
    for (final ShotSize size in kShotSizes) {
      testWidgets('${screen.name} @ ${size.label}', (WidgetTester tester) async {
        await shoot(tester, env: env, screen: screen, size: size);
      });
    }

    testWidgets('${screen.name} @ desktop dark', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: screen,
        size: kShotSizes.last,
        brightness: Brightness.dark,
      );
    });
  }

  // The workbench is eight screens wearing one nav entry, and the loop above
  // only ever photographs tab 0. The crop editor and the prompt assistant —
  // two of the three pages the design spec redraws in full — were therefore
  // never rendered at all, which is how a grid that only appears mid-drag and
  // a composer still wearing the old grey fill both survived a design pass.
  //
  // Each needs its tab's own state seeded before mount, so they take `before`
  // rather than riding the loop.
  for (final _WorkbenchTab tab in _workbenchTabs) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('workbench · ${tab.name} @ desktop ${brightness.name}',
          (WidgetTester tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.workbench,
          size: kShotSizes.last,
          brightness: brightness,
          suffix: tab.name,
          before: (_) async {
            final AppState appState = AppState();
            appState.setWorkbenchTab(tab.index);
            if (!tab.seedOnSettled) tab.seed(appState);
          },
          after: tab.seedOnSettled
              ? (WidgetTester tester) async {
                  tab.seed(AppState());
                  await tester.pump();
                }
              : null,
        );
      });
    }
  }
}

class _WorkbenchTab {
  const _WorkbenchTab(this.name, this.index, this.seed, {this.seedOnSettled = false});
  final String name;
  final int index;
  final void Function(AppState appState) seed;

  /// Seed after the first frame instead of before it.
  ///
  /// For state the screen's own mount would undo: the gallery rescans on
  /// mount and the scan rebuilds its [AppImage] list, dropping a selection
  /// made against the previous instances. Seeding on the settled tree is the
  /// same order a user produces.
  final bool seedOnSettled;
}

/// Indices match the `switch` in `workbench_screen.dart`'s build.
final List<_WorkbenchTab> _workbenchTabs = <_WorkbenchTab>[
  // Tab 0 again, but with pictures selected: the config panel's reference
  // strip is empty otherwise, and the strip is where the selection order the
  // model receives is shown and edited.
  _WorkbenchTab('selection', 0, (AppState s) => seedImageSelection(s), seedOnSettled: true),
  _WorkbenchTab('crop', 3, seedCropSource),
  _WorkbenchTab('assistant', 4, seedOptimizerSession),
];
