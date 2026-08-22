import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_config_panel.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

/// Covers the one thing that decides how often the workbench's right panel
/// rebuilds: whether its parent hands it the *same* widget.
///
/// `context.select` inside a child cannot stop a rebuild pushed down from
/// above. `Element.updateChild` only skips when the old and new widgets are
/// identical, and `Widget` has no `==`, so a freshly allocated
/// `WorkbenchConfigPanel()` from the parent's build rebuilds the panel no
/// matter what it selected. The panel's builder is re-invoked from
/// `_WorkbenchLayoutState.build` — on every splitter drag frame, and on every
/// `AppState` notification through the enclosing screen build — so "freshly
/// allocated" meant "several times a second, for changes it does not read".
///
/// The fix is a const instance, which Dart canonicalises, which makes it
/// identical. That is invisible in a screenshot and cheap to undo by accident,
/// hence this.
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

  /// The harness's own settle: fixed pumps, never `pumpAndSettle`.
  ///
  /// Something on the workbench keeps a frame permanently scheduled, so
  /// `pumpAndSettle` hangs until its timeout rather than returning — which is
  /// why `mountApp` counts pumps instead of asking whether the tree is idle.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Wide enough that the right panel is inline rather than in a drawer.
  const Size desktop = Size(1600, 900);

  testWidgets('an unrelated notification does not re-hand the panel a new widget',
      (tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: desktop,
      label: 'rebuild_scope',
    );

    final before = tester.widget<WorkbenchConfigPanel>(find.byType(WorkbenchConfigPanel));

    // A bare notification, which is what every settings setter ends in and
    // what the screen above listens to.
    //
    // Deliberately not routed through one of those setters. `setConsoleHeight`
    // never calls `notifyListeners` at all, and `setRetryCount` calls it
    // *after* `await _db.saveSetting(...)` — a real write, which never
    // completes inside `testWidgets`' fake-async zone. Either one makes this
    // test pass whether or not the fix is present, by never firing.
    AppState().notify();
    await settle(tester);

    final after = tester.widget<WorkbenchConfigPanel>(find.byType(WorkbenchConfigPanel));
    expect(
      identical(before, after),
      isTrue,
      reason: 'the panel was handed a new widget, so its context.select calls gate nothing',
    );
  });

  testWidgets('the panel is still rebuilt when what it selects changes', (tester) async {
    // The other half of the rule: skipping rebuilds is only correct if the
    // ones that matter still happen. `lastPrompt` is one of the panel's
    // selectors, and the panel syncs its editor from it.
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: desktop,
      label: 'rebuild_scope_live',
    );

    const typed = 'a prompt that came from somewhere else';
    // Deliberately not awaited: the returned future is a real SQLite write,
    // which never progresses inside `testWidgets`' fake-async zone. It does
    // not need to — `updateWorkbenchConfig` moves the field and notifies
    // *before* it writes, which is the whole shape of that method.
    AppState().updateWorkbenchConfig(prompt: typed);
    await settle(tester);

    expect(
      find.descendant(
        of: find.byType(WorkbenchConfigPanel),
        matching: find.text(typed),
      ),
      findsWidgets,
      reason: 'a change the panel selects must still reach it',
    );
  });
}
