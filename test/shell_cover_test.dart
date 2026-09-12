// A settled full-screen cover must stop the shell underneath from painting.
//
// Every assertion here is about the *mechanism*, not about a frame time: a
// wall clock in a widget test is a flake generator, and the milliseconds this
// bought are in `tool/bench/gpu_bench.ps1`'s output and in
// `lib/widgets/shell/shell_cover.dart`'s header. What can regress silently is
// the plumbing — a route that forgets to flip, a flip that never comes back on
// pop, a ground that stays full-window — and that is what these pin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/widgets/app_window_frame.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/shell_cover.dart';

/// The route's own transition, short enough to settle in one pump.
const Duration _reveal = Duration(milliseconds: 120);

/// Whether the subtree under [key] is still ticking.
bool _ticking(GlobalKey key) =>
    TickerMode.valuesOf(key.currentContext!).enabled;

FullScreenCoverRoute<void> _coverRoute() => FullScreenCoverRoute<void>(
      fullscreenDialog: true,
      transitionDuration: _reveal,
      reverseTransitionDuration: _reveal,
      pageBuilder: (_, _, _) => const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );

void main() {
  testWidgets('the shell below stops ticking once the cover settles, and '
      'starts again before the exit shows', (WidgetTester tester) async {
    final controller = ShellCoverController();
    addTearDown(controller.dispose);
    final GlobalKey belowKey = GlobalKey();
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      builder: (context, child) =>
          ShellCover(controller: controller, child: child!),
      home: SizedBox.expand(key: belowKey),
    ));

    // `TickerMode` is the observable side of the Overlay's opaque handling: an
    // opaque entry makes everything below it offstage, which stops its paint,
    // its layout and its tickers together. Asserting on the ticker is how a
    // widget test sees that from the outside.
    expect(_ticking(belowKey), isTrue);
    expect(controller.covered, isFalse);

    navKey.currentState!.push(_coverRoute());
    await tester.pump();

    // Mid-flight the shell must still be live — that is what the Hero flies
    // over, and the whole reason the route cannot just be born opaque.
    await tester.pump(_reveal ~/ 2);
    expect(_ticking(belowKey), isTrue,
        reason: 'the grid has to stay visible under the fade');
    expect(controller.covered, isFalse);

    await tester.pumpAndSettle();
    expect(_ticking(belowKey), isFalse);
    expect(controller.value, 1);

    navKey.currentState!.pop();
    // One pump is the first frame of the exit: by then the shell must be back.
    await tester.pump();
    expect(_ticking(belowKey), isTrue,
        reason: 'didPop fires when the pop starts — a shell that came back '
            'only at the end would flash in for the last frame');
    expect(controller.covered, isFalse);

    await tester.pumpAndSettle();
    expect(controller.value, 0);
  });

  testWidgets('a cover disposed without a pop animation still releases the '
      'shell', (WidgetTester tester) async {
    final controller = ShellCoverController();
    addTearDown(controller.dispose);
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      builder: (context, child) =>
          ShellCover(controller: controller, child: child!),
      home: const SizedBox.expand(),
    ));

    navKey.currentState!.push(_coverRoute());
    await tester.pumpAndSettle();
    expect(controller.value, 1);

    // Tearing the tree down is the path a `removeRoute` or a hot restart
    // takes; a counter that leaked here would leave the ground shrunk
    // forever.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(controller.value, 0);
  });

  testWidgets('two overlapping covers keep the ground shrunk until the last '
      'one leaves', (WidgetTester tester) async {
    final controller = ShellCoverController();
    addTearDown(controller.dispose);
    final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      builder: (context, child) =>
          ShellCover(controller: controller, child: child!),
      home: const SizedBox.expand(),
    ));

    navKey.currentState!.push(_coverRoute());
    await tester.pumpAndSettle();
    navKey.currentState!.push(_coverRoute());
    await tester.pumpAndSettle();
    expect(controller.value, 2);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(controller.covered, isTrue,
        reason: 'the first cover is still there');

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(controller.covered, isFalse);
  });

  testWidgets('the window ground shrinks to the title-bar strip while covered',
      (WidgetTester tester) async {
    final controller = ShellCoverController();
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The ground on its own, in the Stack it lives in inside `AppWindowFrame`.
    // Mounting the whole frame would drag in the real title bar, which wants
    // the app's providers and localizations and has nothing to do with what is
    // under test; the controller is driven directly, and the route that drives
    // it for real is covered above.
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ShellCover(
        controller: controller,
        child: const Stack(children: [WindowGround()]),
      ),
    ));
    await tester.pumpAndSettle();

    Size groundSize() => tester.getSize(find.byType(AuroraBackdrop));

    expect(groundSize(), const Size(1200, 800),
        reason: 'uncovered, the wall is the whole window');

    // The title bar sits above the Navigator, so no route can cover it and it
    // is still real glass with something to refract. Everything below is
    // behind opaque black.
    controller.enter();
    await tester.pumpAndSettle();
    expect(groundSize(), const Size(1200, kTitleBarHeight),
        reason: 'covered, only the strip behind the title bar still shows');

    controller.leave();
    await tester.pumpAndSettle();
    expect(groundSize(), const Size(1200, 800));
  });
}
