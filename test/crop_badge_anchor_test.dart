import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';
import 'screenshots/harness/shoot.dart';

/// The crop tool's size badge — `A3 10e` draws it inside the selection's
/// top-left corner, reading the dimensions a save would actually produce.
///
/// Two things went wrong with it and neither was visible from the code. It was
/// anchored on [EditActionDetails.screenCropRect], which differs from the
/// badge's own Stack by `layoutTopLeft` — 117px here — so it floated well
/// below the rect it labelled. And it only appeared once something had been
/// dragged, which is why nobody saw the first bug: while dragging, the eye is
/// on the handle.
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

  Future<void> openCrop(WidgetTester tester) => mountApp(
        tester,
        env: env,
        screen: AppScreen.workbench,
        size: const Size(1440, 900),
        label: 'crop-badge',
        before: (_) async {
          final AppState s = AppState();
          s.setWorkbenchTab(3);
          seedCropSource(s);
        },
      );

  /// The badge's own text, found by the `×` no other label on this screen uses
  /// between two bare numbers.
  Finder badge() => find.byWidgetPredicate(
        (Widget w) =>
            w is Text && (w.data ?? '').contains('×') && !(w.data ?? '').contains('→'),
      );

  testWidgets('the selection is measured before anything is dragged', (WidgetTester tester) async {
    await openCrop(tester);
    // The editor knows the crop rect from its first layout; the badge used to
    // wait for an edit that may never come.
    expect(badge(), findsOneWidget);
    expect((tester.widget<Text>(badge()).data ?? ''), contains('512 × 512'));
  });

  testWidgets('the badge sits inside the selection it labels', (WidgetTester tester) async {
    await openCrop(tester);

    final dynamic editor = tester.state(find.byType(ExtendedImageEditor).first) as dynamic;
    final Rect selection = editor.editAction!.cropRect as Rect;
    // Stack-local → global. The editor fills the badge's Stack, so its own
    // top-left is that Stack's origin.
    final Rect canvas = tester.getRect(find.byType(ExtendedImage).first);
    final Rect selectionOnScreen = selection.shift(canvas.topLeft);

    final Rect drawn = tester.getRect(badge());
    expect(selectionOnScreen.contains(drawn.topLeft), isTrue,
        reason: 'badge $drawn is outside the selection $selectionOnScreen');
    // Near the corner, not merely somewhere inside it.
    expect(drawn.top - selectionOnScreen.top, lessThan(24));
    expect(drawn.left - selectionOnScreen.left, lessThan(24));
  });
}
