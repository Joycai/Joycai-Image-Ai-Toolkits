import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/screens/workbench/workbench_layout.dart';

/// `⌘\` and `⇧⌘\` are called "show or hide", so on a tablet they have to be
/// able to hide.
///
/// The drawer lives in the workbench's own `Scaffold`, under the screen's key
/// handler, so the chord still reaches that handler while the drawer is up —
/// and `Scaffold.openDrawer()` on an open drawer is a silent no-op. The
/// open-only version therefore looked fine in every test that pressed the key
/// once and was dead on every press after the first. The file browser's
/// narrow branch has always toggled; this is the workbench catching up.
void main() {
  Future<GlobalKey<ScaffoldState>> mountScaffold(WidgetTester tester) async {
    final key = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: key,
          drawer: const Drawer(child: SizedBox.shrink()),
          endDrawer: const Drawer(child: SizedBox.shrink()),
          body: const SizedBox.expand(),
        ),
      ),
    );
    return key;
  }

  WorkbenchLayoutState layoutFor(GlobalKey<ScaffoldState> key) =>
      WorkbenchLayoutState(key, contentWidth: 900, leftInDrawer: true, rightInDrawer: true);

  testWidgets('toggleLeftPanel closes a drawer it opened', (tester) async {
    final key = await mountScaffold(tester);
    final layout = layoutFor(key);

    expect(key.currentState!.isDrawerOpen, isFalse);

    layout.toggleLeftPanel();
    await tester.pumpAndSettle();
    expect(key.currentState!.isDrawerOpen, isTrue);

    layout.toggleLeftPanel();
    await tester.pumpAndSettle();
    expect(
      key.currentState!.isDrawerOpen,
      isFalse,
      reason:
          'the second press hides it — `openDrawer` on an open drawer '
          'is a no-op, which is what left the chord dead',
    );
  });

  testWidgets('toggleRightPanel closes an end drawer it opened', (tester) async {
    final key = await mountScaffold(tester);
    final layout = layoutFor(key);

    layout.toggleRightPanel();
    await tester.pumpAndSettle();
    expect(key.currentState!.isEndDrawerOpen, isTrue);

    layout.toggleRightPanel();
    await tester.pumpAndSettle();
    expect(key.currentState!.isEndDrawerOpen, isFalse);
  });

  testWidgets('the phone sheet has no close, and says so by opening', (tester) async {
    final key = await mountScaffold(tester);
    var opened = 0;
    final layout = WorkbenchLayoutState(
      key,
      contentWidth: 380,
      leftInDrawer: true,
      rightInDrawer: false,
      rightSheetOpener: () => opened++,
    );

    // A modal sheet is a route of its own and takes the keyboard with it, so
    // no key can reach this handler while it is up. Opening is the whole
    // contract there, and the toggle must not reach past it to the end
    // drawer that is not the panel.
    layout.toggleRightPanel();
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(key.currentState!.isEndDrawerOpen, isFalse);
  });
}
