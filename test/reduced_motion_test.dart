import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_segmented_control.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_text_field.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_side_panel.dart';

/// Pins the app's answer to the platform's reduce-motion flag.
///
/// The flag is a single boolean, and every animated widget in the app has to
/// read it — which is exactly the shape of thing that gets wired up once, in
/// one component, and then quietly skipped by the next twenty. So the contract
/// is tested at the token (`AppMotion.durationOf`, which everything routes
/// through) and at the one place that deliberately does *not* collapse to zero.
void main() {
  /// Mounts [child] with the platform flag forced either way.
  ///
  /// The override goes through `MaterialApp.builder` rather than around the
  /// app: it has to sit *inside* the Navigator, or a pushed route builds
  /// against the view's own MediaQuery and never sees the flag. Wrapping the
  /// MaterialApp instead is the version of this that silently tests nothing.
  Widget harness({required bool disableAnimations, required Widget child}) {
    return MaterialApp(
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
        child: navigator!,
      ),
      home: Scaffold(body: child),
    );
  }

  /// Widens the test surface past the tablet breakpoint.
  ///
  /// `AppSidePanel.show` branches on `Responsive.isNarrow` before it branches
  /// on anything else, and the default 800×600 test window is below the 1000px
  /// tablet breakpoint — so without this the side-panel tests exercise the
  /// bottom-sheet path and assert against `showModalBottomSheet`'s own 250ms,
  /// which is what the first draft of this file did.
  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('AppMotion.durationOf', () {
    testWidgets('hands back the token when the platform is happy with motion',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(harness(
        disableAnimations: false,
        child: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ));

      expect(AppMotion.prefersReduced(ctx), isFalse);
      for (final token in [
        AppMotion.hover,
        AppMotion.state,
        AppMotion.reveal,
        AppMotion.panel,
      ]) {
        expect(AppMotion.durationOf(ctx, token), token);
      }
    });

    testWidgets('collapses every token to zero when it is not', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(harness(
        disableAnimations: true,
        child: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ));

      expect(AppMotion.prefersReduced(ctx), isTrue);
      for (final token in [
        AppMotion.hover,
        AppMotion.state,
        AppMotion.reveal,
        AppMotion.panel,
      ]) {
        expect(AppMotion.durationOf(ctx, token), Duration.zero);
      }
    });

    testWidgets('reaches a real widget, not just the token', (tester) async {
      // AppTextField's focus ring stands in for the AnimatedContainers that
      // took the same edit across ~20 files. If the pass missed a file, it
      // missed it this way.
      await tester.pumpWidget(harness(
        disableAnimations: true,
        child: const AppTextField(label: 'Key'),
      ));
      expect(
        tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .map((w) => w.duration),
        everyElement(Duration.zero),
      );

      await tester.pumpWidget(harness(
        disableAnimations: false,
        child: const AppTextField(label: 'Key'),
      ));
      expect(
        tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
            .map((w) => w.duration),
        everyElement(AppMotion.hover),
      );
    });

    testWidgets('reaches the segmented control indicator too',
        (tester) async {
      // A different animated primitive, deliberately: the indicator is an
      // AnimatedPositioned, so it would not have been caught by the sweep
      // above even if it had been missed.
      Widget control() => AppSegmentedControl<int>(
            segments: const [
              AppSegment(value: 0, label: 'A'),
              AppSegment(value: 1, label: 'B'),
            ],
            value: 0,
            onChanged: (_) {},
          );

      for (final (disabled, expected) in [
        (true, Duration.zero),
        (false, AppMotion.state),
      ]) {
        await tester.pumpWidget(harness(disableAnimations: disabled, child: control()));
        // The indicator is positioned from a measurement taken after layout,
        // so it does not exist on the first frame.
        await tester.pump();

        final positioned = tester
            .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .map((w) => w.duration);
        expect(positioned, isNotEmpty, reason: 'disabled=$disabled');
        expect(positioned, everyElement(expected), reason: 'disabled=$disabled');
      }
    });
  });

  group('AppSidePanel is the documented exception', () {
    testWidgets('slides in when motion is allowed', (tester) async {
      useDesktopSurface(tester);
      await tester.pumpWidget(harness(
        disableAnimations: false,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppSidePanel.show(
              context,
              builder: (_) => const Text('panel body'),
            ),
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Scoped to the panel's own ancestors. `find.byType(SlideTransition)`
      // unscoped would also match anything Scaffold or the barrier happens to
      // use, and `find.descendant` would match nothing in either case — the
      // transition wraps AppSidePanel, it is not inside it.
      expect(
        find.ancestor(
          of: find.byType(AppSidePanel),
          matching: find.byType(SlideTransition),
        ),
        findsWidgets,
      );
      await tester.pumpAndSettle();
      expect(find.text('panel body'), findsOneWidget);
    });

    testWidgets('cross-fades instead of cutting, so arrival is still visible',
        (tester) async {
      useDesktopSurface(tester);
      // The point of the exception: 450px of panel appearing between two
      // frames reads as the screen having changed. A zero duration here would
      // be the bug, not the fix — so this asserts the transition is a fade
      // *and* that it still takes time.
      await tester.pumpWidget(harness(
        disableAnimations: true,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppSidePanel.show(
              context,
              builder: (_) => const Text('panel body'),
            ),
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final route = ModalRoute.of(
        tester.element(find.text('panel body')),
      )!;
      expect(route.transitionDuration, AppMotion.reveal);

      // A fade, and no travel: the panel must never be off-centre from where
      // it lands. Both finders are ancestor-scoped to the panel, which is
      // where its own transition lives — the mirror of the test above.
      expect(
        find.ancestor(
          of: find.byType(AppSidePanel),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.byType(AppSidePanel),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      expect(find.text('panel body'), findsOneWidget);
    });
  });
}
