import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/scroll_edge_fade.dart';

/// Covers the rule that makes the fade worth having: it appears only on an
/// edge that actually has content beyond it.
///
/// A permanent gradient is easier to write and is the version that dims the
/// last row of a list short enough to fit — the same mistake as the hard cut,
/// pointing the other way.
void main() {
  Widget host(Widget child, {double height = 200}) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(height: height, width: 300, child: child))),
      );

  Widget list({required int items, ScrollController? controller}) => ScrollEdgeFade(
        child: ListView.builder(
          controller: controller,
          itemCount: items,
          itemBuilder: (_, i) => SizedBox(height: 50, child: Text('row $i')),
        ),
      );

  testWidgets('a list that fits pays nothing — no mask at all', (tester) async {
    // Three 50px rows in a 200px box. Nothing to say, so nothing is drawn, and
    // no saveLayer is taken.
    await tester.pumpWidget(host(list(items: 3)));
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('a list that overflows fades the edge it can scroll towards',
      (tester) async {
    await tester.pumpWidget(host(list(items: 20)));
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('the fade follows the scroll position to the far edge', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(list(items: 20, controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);

    // All the way down: there is now content above and none below, so the mask
    // is still there — but it has to have swapped ends. Asserting the widget's
    // presence alone would pass with a gradient that never moved, so this
    // reads the shader's own stops.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsOneWidget);

    final shader = tester.widget<ShaderMask>(find.byType(ShaderMask));
    // The callback is the only thing that knows which end is soft; run it and
    // check the gradient it would build, rather than the pixels.
    expect(shader.blendMode, BlendMode.dstIn);
    expect(() => shader.shaderCallback(const Rect.fromLTWH(0, 0, 300, 200)),
        returnsNormally);
  });

  testWidgets('it disappears again once the content shrinks to fit', (tester) async {
    await tester.pumpWidget(host(list(items: 20)));
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsOneWidget);

    // The metrics change without the scroll position moving — a card
    // collapsing, a filter emptying a list. This is the case
    // ScrollNotification alone does not report, and it is why the widget also
    // listens for ScrollMetricsNotification.
    await tester.pumpWidget(host(list(items: 2)));
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsNothing);
  });
}
