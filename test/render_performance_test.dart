// Guards for the render-performance invariants that fail silently.
//
// None of these assert on a frame time — a wall clock in a widget test is a
// flake generator. Each asserts on the *structure* that made a frame cheap, so
// a regression shows up as a failing expectation rather than as a laptop fan.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/core/thumbnail_decode.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_breathing_dot.dart';

void main() {
  group('thumbnail size snapping', () {
    test('a slider sweep collapses onto a handful of distinct sizes', () {
      // The grid lays out by column count, so most of a drag's pointer events
      // ask for a picture identical to the last one. Measured over the real
      // gallery, snapping took a full 80→400 drag from ~337k widget builds to
      // ~46k.
      final Set<double> distinct = <double>{
        for (double v = 80; v <= 400; v += 1) snapThumbnailSize(v),
      };
      expect(distinct.length, lessThan(50));
      expect(distinct.length, greaterThan(20),
          reason: 'coarse enough to stop being smooth would be a real loss');
    });

    test('both ends of the slider stay reachable', () {
      // Both grids run 80..400; a step that either end did not land on would
      // quietly take the extreme away from the user.
      expect(snapThumbnailSize(80), 80);
      expect(snapThumbnailSize(400), 400);
    });

    test('snapping is stable — a snapped value snaps to itself', () {
      for (double v = 80; v <= 400; v += 1) {
        final double once = snapThumbnailSize(v);
        expect(snapThumbnailSize(once), once);
      }
    });
  });

  testWidgets(
    'the breathing dot keeps its repaint inside a boundary',
    (WidgetTester tester) async {
      // `00 · 1e`: this is the app's one looping animation, and the task
      // capsule in the shell puts it inside a BackdropFilter on every screen.
      // Without a boundary between the two, each breath marked the glass
      // dirty and re-recorded the blur sixty times a second for as long as
      // any task was running.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: AppBreathingDot(color: Colors.blue)),
          ),
        ),
      );

      final Finder animated = find.descendant(
        of: find.byType(AppBreathingDot),
        matching: find.byType(FadeTransition),
      );
      expect(
        animated,
        findsOneWidget,
        reason: 'the dot must animate by repainting (FadeTransition), not by '
            'rebuilding an Opacity in a builder',
      );

      // Walk up from the render object that calls markNeedsPaint each frame.
      // The first boundary above it must belong to the dot itself, not to
      // whatever the dot happens to have been dropped into.
      final List<String> crossed = <String>[];
      String? boundary;
      tester.element(animated).visitAncestorElements((Element a) {
        if (a.renderObject?.isRepaintBoundary ?? false) {
          boundary = a.widget.runtimeType.toString();
          return false;
        }
        crossed.add(a.widget.runtimeType.toString());
        return true;
      });

      expect(boundary, 'RepaintBoundary');
      expect(
        crossed,
        isEmpty,
        reason: 'the boundary must sit directly above the animation, inside '
            'AppBreathingDot — a caller cannot be relied on to add one',
      );
    },
  );

  testWidgets('a dot that is not breathing is fully opaque',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppBreathingDot(color: Colors.blue, breathing: false),
          ),
        ),
      ),
    );
    final FadeTransition fade = tester.widget(
      find.descendant(
        of: find.byType(AppBreathingDot),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1.0);
  });

  group('glass nesting', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Center(child: child))),
        );

    testWidgets('a lens on glass does not sample the window twice',
        (WidgetTester tester) async {
      // A nested backdrop filter samples its parent's already blurred,
      // already saturated, fill-covered output. The workbench carried seven
      // of these at once against the ceiling of three in AppGlass's own doc —
      // three of them lenses sitting on a bar.
      await pump(
        tester,
        const AppGlass(
          grade: GlassGrade.bar,
          child: AppGlass(grade: GlassGrade.lens, child: SizedBox.square(dimension: 20)),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('a lens standing on its own keeps its blur',
        (WidgetTester tester) async {
      await pump(
        tester,
        const AppGlass(grade: GlassGrade.lens, child: SizedBox.square(dimension: 20)),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('a float on glass keeps its own blur', (WidgetTester tester) async {
      // Grade-scoped on purpose: a menu, a sheet or a snackbar overhangs
      // whatever it opened from, and an OverlayPortal leaves it under that
      // widget in the element tree even though it is drawn outside it.
      await pump(
        tester,
        const AppGlass(
          grade: GlassGrade.bar,
          child: AppGlass(grade: GlassGrade.float, child: SizedBox.square(dimension: 20)),
        ),
      );
      expect(find.byType(BackdropFilter), findsNWidgets(2));
    });

    testWidgets('the tinted CTA does not re-blur the bar it stands on',
        (WidgetTester tester) async {
      await pump(
        tester,
        const AppGlass(
          grade: GlassGrade.bar,
          child: AppTintedGlass(child: SizedBox.square(dimension: 20)),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('off glass, the tinted CTA is the first layer and blurs',
        (WidgetTester tester) async {
      await pump(tester, const AppTintedGlass(child: SizedBox.square(dimension: 20)));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });
}
