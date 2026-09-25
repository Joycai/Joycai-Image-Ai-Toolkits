import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/folder_outline_geometry.dart';

/// The folder outline jumps to offsets it computed, not measured — so the
/// computation has to agree with the real sliver layout to the pixel, and
/// the section lookup has to land on the right side of every boundary.
void main() {
  group('columns and cell extent', () {
    test('match SliverGridDelegateWithMaxCrossAxisExtent', () {
      // 1000 wide, 150 tiles, 12 gutter: ceil(1000/162) = 7 columns,
      // (1000 - 72) / 7 wide each.
      final columns = FolderOutlineGeometry.columnsFor(
        crossAxisExtent: 1000,
        maxCrossAxisExtent: 150,
        spacing: 12,
      );
      expect(columns, 7);
      expect(
        FolderOutlineGeometry.cellExtentFor(crossAxisExtent: 1000, columns: columns, spacing: 12),
        closeTo(928 / 7, 1e-9),
      );
    });

    test('never fewer than one column', () {
      expect(
        FolderOutlineGeometry.columnsFor(crossAxisExtent: 40, maxCrossAxisExtent: 150, spacing: 12),
        1,
      );
      expect(
        FolderOutlineGeometry.columnsFor(crossAxisExtent: 0, maxCrossAxisExtent: 150, spacing: 12),
        1,
      );
    });
  });

  group('sectionOffsets', () {
    test('accumulates header, padding and rows per section', () {
      // Two columns, 100 cells, 10 gutter, 30 header, 5 top inset.
      // Section 0: 3 files → 2 rows → 30 + 10 + (200 + 10) + 10 = 260.
      // Section 1: 2 files → 1 row  → 30 + 10 + 100 + 10 = 150.
      final offsets = FolderOutlineGeometry.sectionOffsets(
        counts: [3, 2, 1],
        columns: 2,
        cellExtent: 100,
        headerExtent: 30,
        spacing: 10,
        topInset: 5,
      );
      expect(offsets, [5, 265, 415]);
    });

    test('an empty section still costs its header and padding', () {
      final offsets = FolderOutlineGeometry.sectionOffsets(
        counts: [0, 1],
        columns: 3,
        cellExtent: 50,
        headerExtent: 20,
        spacing: 8,
      );
      expect(offsets, [0, 36]);
    });

    test('a list is one column with no spacing', () {
      final offsets = FolderOutlineGeometry.sectionOffsets(
        counts: [4, 4],
        columns: 1,
        cellExtent: 44,
        headerExtent: 32,
        spacing: 0,
      );
      expect(offsets, [0, 32 + 4 * 44]);
    });
  });

  group('sectionAt', () {
    const offsets = [0.0, 260.0, 520.0];

    test('is -1 with no sections', () {
      expect(FolderOutlineGeometry.sectionAt(const [], 100), -1);
    });

    test('is the first section before any header has scrolled off', () {
      expect(FolderOutlineGeometry.sectionAt(offsets, 0), 0);
      expect(FolderOutlineGeometry.sectionAt(offsets, 259), 0);
    });

    test('flips exactly when a header reaches the top', () {
      expect(FolderOutlineGeometry.sectionAt(offsets, 260), 1);
      expect(FolderOutlineGeometry.sectionAt(offsets, 519), 1);
      expect(FolderOutlineGeometry.sectionAt(offsets, 520), 2);
      expect(FolderOutlineGeometry.sectionAt(offsets, 9999), 2);
    });

    test('an animation that stops half a pixel short still counts', () {
      expect(FolderOutlineGeometry.sectionAt(offsets, 259.6), 1);
      expect(FolderOutlineGeometry.sectionAt(offsets, 259.4), 0);
    });

    test('a negative overscroll is the first section', () {
      expect(FolderOutlineGeometry.sectionAt(offsets, -40), 0);
    });
  });

  testWidgets('the computed offsets are where the real slivers land', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const counts = [9, 4, 13];
    const gap = 12.0;
    const header = 34.0;
    const tile = 150.0;
    const topInset = 40.0;
    final headerKeys = List.generate(counts.length, (_) => GlobalKey());
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: topInset)),
            for (var i = 0; i < counts.length; i++) ...[
              SliverToBoxAdapter(
                child: SizedBox(key: headerKeys[i], height: header),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(gap),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: tile,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: 1,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, _) => const ColoredBox(color: Colors.red),
                    childCount: counts[i],
                  ),
                ),
              ),
            ],
            // Enough tail that every header can reach the top.
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    );

    final columns = FolderOutlineGeometry.columnsFor(
      crossAxisExtent: 1000 - gap * 2,
      maxCrossAxisExtent: tile,
      spacing: gap,
    );
    final cell = FolderOutlineGeometry.cellExtentFor(
      crossAxisExtent: 1000 - gap * 2,
      columns: columns,
      spacing: gap,
    );
    final offsets = FolderOutlineGeometry.sectionOffsets(
      counts: counts,
      columns: columns,
      cellExtent: cell,
      headerExtent: header,
      spacing: gap,
      topInset: topInset,
    );

    for (var i = 0; i < counts.length; i++) {
      controller.jumpTo(offsets[i]);
      await tester.pump();
      final top = tester.getTopLeft(find.byKey(headerKeys[i])).dy;
      expect(top, closeTo(0, 0.01), reason: 'section $i header');
    }
  });
}
