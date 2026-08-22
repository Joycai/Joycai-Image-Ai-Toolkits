import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_segmented_control.dart';

/// Covers the selection indicator, which used to be each chip's own fill.
///
/// The old control crossfaded: two chips, each animating a decoration of its
/// own. That cannot describe *one thing moving*, which is the whole claim a
/// track-shaped control makes — "you are here, along this". The indicator is
/// now a single positioned pill measured against the selected chip, so these
/// tests are mostly about that measurement being right, since a wrong one is
/// visibly broken rather than merely unanimated.
void main() {
  const seed = Colors.indigo;

  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
        home: Scaffold(body: Center(child: child)),
      );

  /// Segments with deliberately unequal label widths — the case an
  /// index-fraction indicator would get wrong and only this can catch.
  List<AppSegment<int>> segments() => const [
        AppSegment(value: 0, label: 'A'),
        AppSegment(value: 1, label: 'A much longer label'),
        AppSegment(value: 2, label: 'Mid'),
      ];

  Widget control(int value, {bool expand = false}) => AppSegmentedControl<int>(
        segments: segments(),
        value: value,
        onChanged: (_) {},
        expand: expand,
      );

  Rect indicatorRect(WidgetTester tester) {
    final positioned = tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
    return Rect.fromLTWH(
      positioned.left!,
      positioned.top!,
      positioned.width!,
      positioned.height!,
    );
  }

  /// The chip's box in the same coordinate space the indicator is positioned in.
  Rect chipRect(WidgetTester tester, String label) {
    final stack = tester.renderObject<RenderBox>(find.byType(Stack).first);
    final chip = tester.renderObject<RenderBox>(
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
    );
    return chip.localToGlobal(Offset.zero, ancestor: stack) & chip.size;
  }

  testWidgets('the indicator lands on the selected chip, not on a fraction of the track',
      (tester) async {
    await tester.pumpWidget(host(control(1)));
    await tester.pump(); // the measurement is taken after layout

    expect(find.byType(AnimatedPositioned), findsOneWidget);
    // Exact, not approximate: the indicator is measured off the chip, so any
    // drift means the measurement is reading the wrong box.
    expect(indicatorRect(tester), chipRect(tester, 'A much longer label'));
  });

  testWidgets('it moves to the new chip and takes its width with it', (tester) async {
    await tester.pumpWidget(host(control(1)));
    await tester.pump();
    final wide = indicatorRect(tester);

    await tester.pumpWidget(host(control(0)));
    await tester.pump();
    final narrow = indicatorRect(tester);

    // Travelled left, and shrank to the shorter label. A pill that only moved
    // would leave the 'A' chip wearing a box sized for a sentence.
    expect(narrow.left, lessThan(wide.left));
    expect(narrow.width, lessThan(wide.width));
    expect(narrow, chipRect(tester, 'A'));
  });

  testWidgets('it is animated, and with the two-endpoint curve', (tester) async {
    // `move`, not `enter`: both the old position and the new one are on
    // screen, so the travel accelerates and decelerates rather than only
    // landing softly.
    await tester.pumpWidget(host(control(2)));
    await tester.pump();

    final positioned = tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
    expect(positioned.duration, AppMotion.state);
    expect(positioned.curve, AppMotion.move);
  });

  testWidgets('an expand track still measures its own chips', (tester) async {
    // Equal widths here, so this would pass even with a fraction-based
    // indicator — it is here because `expand` wraps every chip in an Expanded,
    // which is the layer the measurement has to see through.
    await tester.pumpWidget(host(SizedBox(width: 600, child: control(2, expand: true))));
    await tester.pump();

    expect(indicatorRect(tester), chipRect(tester, 'Mid'));
  });

  testWidgets('the first frame still shows a selection', (tester) async {
    // Before the measurement lands there is no indicator, so the chip draws
    // the skin itself. Without that the control renders one frame with nothing
    // chosen — a flicker on every screen that builds one.
    await tester.pumpWidget(host(control(1)));
    // Deliberately no second pump.

    expect(find.byType(AnimatedPositioned), findsNothing);
    final selected = tester.widget<Container>(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('A much longer label'),
              matching: find.byType(InkWell),
            ),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(selected.decoration, isNotNull);
  });
}
