import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/drag/app_reorder_gap.dart';

/// `AppReorderGap`: the 00d 「空位即落点」 indicator, found in the gap the
/// framework's reorderable list opens.
///
/// What is pinned is the part that relies on how the framework builds that
/// gap — an empty box in the dragged item's old slot, the items in between
/// slid by one extent. If a Flutter upgrade changes that, these fail rather
/// than the indicator silently vanishing.
void main() {
  const double rowHeight = 40;
  const double rowGap = 4;

  late AppReorderGapController gap;
  late List<String> items;
  int drops = 0;

  Future<void> pumpList(WidgetTester tester) async {
    items = ['A', 'B', 'C', 'D', 'E', 'F'];
    drops = 0;
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppReorderGap(
              itemCount: items.length,
              slotPadding: const EdgeInsets.only(bottom: rowGap),
              builder: (context, controller) {
                gap = controller;
                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: items.length,
                  onReorderStart: controller.onReorderStart(),
                  onReorderItem: controller.onReorderItem((oldIndex, newIndex) {
                    drops++;
                    setState(() => items.insert(newIndex, items.removeAt(oldIndex)));
                  }),
                  itemBuilder: (context, index) => controller.item(
                    key: ValueKey(items[index]),
                    index: index,
                    child: ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: rowGap),
                        child: SizedBox(height: rowHeight - rowGap, child: Text(items[index])),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('nothing is painted until a drag starts', (tester) async {
    await pumpList(tester);
    expect(gap.debugGaps, isEmpty);
    expect(gap.debugLabel, isNull);
  });

  testWidgets('dragging a row down paints one row-sized gap where it would land, with its position', (tester) async {
    await pumpList(tester);

    final drag = await tester.startGesture(tester.getCenter(find.text('A')));
    await tester.pump(const Duration(milliseconds: 50));
    await drag.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
    // Past B and C: the drop lands in the third place.
    await drag.moveBy(const Offset(0, rowHeight * 2.5));
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(gap.debugGaps, hasLength(1), reason: 'gaps: ${gap.debugGaps}');
    final rect = gap.debugGaps.single;
    // Inset by the row's own gap at the bottom.
    expect(rect.height, closeTo(rowHeight - rowGap, 0.5));
    expect(rect.top, closeTo(rowHeight * 2, 0.5), reason: 'the gap should sit in the third slot: $rect');
    expect(gap.debugLabel, 'Drop at 3');

    await drag.up();
    await tester.pumpAndSettle();

    expect(drops, 1);
    expect(items.take(3), ['B', 'C', 'A']);
  });

  testWidgets('dragging to the bottom says it drops at the end', (tester) async {
    await pumpList(tester);

    final drag = await tester.startGesture(tester.getCenter(find.text('B')));
    await tester.pump(const Duration(milliseconds: 50));
    await drag.moveBy(const Offset(0, rowHeight * 6));
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(gap.debugGaps, hasLength(1), reason: 'gaps: ${gap.debugGaps}');
    expect(gap.debugLabel, 'Drop at end');
    await drag.up();
    await tester.pumpAndSettle();
    expect(items.last, 'B');
  });

  testWidgets('a drop that moved the row confirms it, then the ring goes', (tester) async {
    await pumpList(tester);

    final drag = await tester.startGesture(tester.getCenter(find.text('A')));
    await tester.pump(const Duration(milliseconds: 50));
    await drag.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await drag.moveBy(const Offset(0, rowHeight * 2.5));
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    // The drop animation, then a couple of frames of the ring.
    for (int i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(drops, 1);
    expect(gap.debugGaps, isEmpty);
    expect(gap.debugConfirming, isTrue);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(gap.debugConfirming, isFalse);
  });
}
