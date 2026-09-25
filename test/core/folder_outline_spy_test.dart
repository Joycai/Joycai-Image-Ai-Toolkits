import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/folder_outline_spy.dart';

/// The spy publishes one integer as the user scrolls, and moves the view
/// when asked. Nothing else may depend on it: the grid does not subscribe.
void main() {
  Widget host(ScrollController controller, {double extent = 3000}) => Directionality(
    textDirection: TextDirection.ltr,
    child: SingleChildScrollView(
      controller: controller,
      child: SizedBox(height: extent),
    ),
  );

  testWidgets('follows the scroll position across section boundaries', (tester) async {
    final controller = ScrollController();
    final spy = FolderOutlineSpy();
    addTearDown(controller.dispose);
    addTearDown(spy.dispose);

    await tester.pumpWidget(host(controller));
    spy
      ..attach(controller)
      ..layout(counts: const [2, 2, 2], columns: 1, cellExtent: 100, headerExtent: 20, spacing: 0);
    // Sections at 0, 220, 440.
    expect(spy.offsets, [0, 220, 440]);
    expect(spy.currentIndex.value, 0);

    final seen = <int>[];
    spy.currentIndex.addListener(() => seen.add(spy.currentIndex.value));

    controller.jumpTo(219);
    expect(spy.currentIndex.value, 0);
    controller.jumpTo(220);
    expect(spy.currentIndex.value, 1);
    controller.jumpTo(700);
    expect(spy.currentIndex.value, 2);
    controller.jumpTo(10);
    expect(spy.currentIndex.value, 0);
    // One notification per change, none for a scroll that stays put.
    expect(seen, [1, 2, 0]);
  });

  testWidgets('layout with the same inputs recomputes nothing', (tester) async {
    final controller = ScrollController();
    final spy = FolderOutlineSpy();
    addTearDown(controller.dispose);
    addTearDown(spy.dispose);
    await tester.pumpWidget(host(controller));
    spy.attach(controller);

    void lay() =>
        spy.layout(counts: [3, 1], columns: 2, cellExtent: 50, headerExtent: 10, spacing: 4);
    lay();
    final first = spy.offsets;
    lay();
    expect(identical(spy.offsets, first), isTrue);

    spy.layout(counts: [3, 1], columns: 3, cellExtent: 50, headerExtent: 10, spacing: 4);
    expect(identical(spy.offsets, first), isFalse);
  });

  testWidgets('scrollTo jumps with a zero duration and animates otherwise', (tester) async {
    final controller = ScrollController();
    final spy = FolderOutlineSpy();
    addTearDown(controller.dispose);
    addTearDown(spy.dispose);
    await tester.pumpWidget(host(controller));
    spy
      ..attach(controller)
      ..layout(counts: const [5, 5, 5], columns: 1, cellExtent: 100, headerExtent: 0, spacing: 0);

    await spy.scrollTo(2, duration: Duration.zero);
    expect(controller.offset, 1000);
    expect(spy.currentIndex.value, 2);

    final animation = spy.scrollTo(1, duration: const Duration(milliseconds: 200));
    // The ticker's first frame is at elapsed zero; the next one is mid-way.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(500));
    expect(controller.offset, lessThan(1000));
    await tester.pumpAndSettle();
    await animation;
    expect(controller.offset, 500);
    expect(spy.currentIndex.value, 1);
  });

  testWidgets('a target past the end clamps to the scroll extent', (tester) async {
    final controller = ScrollController();
    final spy = FolderOutlineSpy();
    addTearDown(controller.dispose);
    addTearDown(spy.dispose);
    // 3000 tall in a 600 tall window: max scroll 2400.
    await tester.pumpWidget(host(controller));
    spy
      ..attach(controller)
      ..layout(
        counts: const [1, 1],
        columns: 1,
        cellExtent: 100,
        headerExtent: 0,
        spacing: 0,
        topInset: 2800,
      );
    expect(spy.targetOffsetOf(1), controller.position.maxScrollExtent);
    expect(spy.targetOffsetOf(5), isNull);
    expect(spy.targetOffsetOf(-1), isNull);
  });

  testWidgets('detach stops listening', (tester) async {
    final controller = ScrollController();
    final spy = FolderOutlineSpy();
    addTearDown(controller.dispose);
    addTearDown(spy.dispose);
    await tester.pumpWidget(host(controller));
    spy
      ..attach(controller)
      ..layout(counts: const [1, 1], columns: 1, cellExtent: 100, headerExtent: 0, spacing: 0);
    spy.detach();
    controller.jumpTo(500);
    expect(spy.currentIndex.value, 0);
  });
}
