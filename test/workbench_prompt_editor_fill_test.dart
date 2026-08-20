import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_config_panel.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/markdown_editor.dart';


import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

/// Covers the workbench right panel's one layout rule: the prompt editor fills
/// whatever height the rest of the panel leaves, and the panel scrolls only
/// once there is not enough of it to go round.
///
/// This is worth pinning because it is held by an arrangement rather than by a
/// number — a viewport-height floor, an [IntrinsicHeight] asking the column how
/// tall it wants to be, and a minimum the editor reports so that question has a
/// sane answer. Any of the three going missing looks fine at one window height
/// and wrong at the next, which is exactly what a sweep catches and a single
/// mount does not.
///
/// The heights are deliberately either side of the changeover rather than round
/// numbers: what matters is that *both* regimes are exercised, and that the
/// editor never collapses in either.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    // Same order the screenshot suite uses, and for the same reasons: the
    // environment before the first AppState(), the seed before loadSettings()
    // reads it back, and a real-async delay because setUpAll is the only place
    // the compute()-based gallery scan actually finishes.
    env = installFixtureEnv(binding);
    await seedFixtures(env);

    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  /// Height of the box that carries the editor's minimum.
  ///
  /// Found by the promise it makes rather than by its type: the panel is full
  /// of [ConstrainedBox]es, and the one that matters is whichever declares
  /// [kMinPromptEditorHeight]. Measuring the [MarkdownEditor] itself would be
  /// measuring the card's contents net of its padding and its footer row —
  /// a number that moves whenever either of those does, for reasons that have
  /// nothing to do with this rule.
  double editorBoxHeight(WidgetTester tester) {
    final finder = find.descendant(
      of: find.byType(WorkbenchConfigPanel),
      matching: find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.minHeight == kMinPromptEditorHeight,
      ),
    );
    expect(finder, findsOneWidget,
        reason: 'nothing in the panel declares the prompt editor a minimum height');
    // Sanity: the editor really is inside the box being measured.
    expect(
      find.descendant(of: finder, matching: find.byType(MarkdownEditor)),
      findsOneWidget,
      reason: 'the minimum-height box no longer wraps the prompt editor',
    );
    return tester.getSize(finder).height;
  }

  // Wide enough that the right panel is inline rather than in a drawer at every
  // height below — the panel has to exist before its height means anything.
  const double width = 1600;

  final Map<String, double> heights = {
    'cramped': 700,
    'default': 900,
    'tall': 1200,
    'very tall': 1600,
  };

  for (final entry in heights.entries) {
    testWidgets('the prompt editor survives a ${entry.key} window', (tester) async {
      await mountApp(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: Size(width, entry.value),
        label: 'fill_${entry.key}',
      );

      final height = editorBoxHeight(tester);

      // The floor. An `expands: true` field reports no height of its own, so
      // without the minimum the panel would crush the editor to nothing before
      // it ever decided to scroll — the failure this arrangement exists to
      // prevent, and the one that is invisible until the window gets short.
      expect(
        height,
        greaterThanOrEqualTo(kMinPromptEditorHeight - 1),
        reason: 'the editor was squeezed below its declared minimum',
      );

      // Nothing may overflow at any of these heights. Drained rather than
      // ignored: `mountApp` leaves the queue empty, so anything here is ours.
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('extra window height goes to the editor, not to whitespace',
      (tester) async {
    // The point of the whole arrangement. Measured here rather than carried
    // over from the sweep above, because leaning on test order to share state
    // is how a suite starts passing for the wrong reason.
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(width, 900),
      label: 'fill_compare_short',
    );
    final short = editorBoxHeight(tester);

    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(width, 1600),
      label: 'fill_compare_tall',
    );
    final tall = editorBoxHeight(tester);

    expect(
      tall,
      greaterThan(short),
      reason: 'the editor did not take the room a taller window gave it — '
          'the panel is scrolling when it should be filling',
    );
  });
}
