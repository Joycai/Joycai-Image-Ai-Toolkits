// Guards for the render-performance invariants that fail silently.
//
// None of these assert on a frame time — a wall clock in a widget test is a
// flake generator. Each asserts on the *structure* that made a frame cheap, so
// a regression shows up as a failing expectation rather than as a laptop fan.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/widgets/app_breathing_dot.dart';

void main() {
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
}
