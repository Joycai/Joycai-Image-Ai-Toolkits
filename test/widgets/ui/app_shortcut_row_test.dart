// `AppShortcutRow`: the keys wrap rather than push the name out, or past
// the row's edge.
//
// The ⌘/ panel's delete row overflowed on macOS only: there it carries a
// third chord (`⌘Backspace`, `macOSOnly`), and once the mono role stopped
// resolving to the UI font in the harness its key caps outgrew the column.
// These widths are narrow enough that the two chords every platform has
// cannot fit either, so the test fails the same way on Linux CI as on a Mac.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/core/app_shortcuts.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_key_label.dart';

void main() {
  const Key labelKey = ValueKey<String>('label');

  Future<void> pumpRow(WidgetTester tester, String id, double width) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: AppShortcutRow(
                gap: 10,
                shortcut: AppShortcuts.byId(id),
                label: const Text(
                  'Delete folder',
                  key: labelKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final double width in <double>[240, 200]) {
    testWidgets('delete at $width: keys wrap, nothing overflows', (WidgetTester tester) async {
      await pumpRow(tester, AppShortcutIds.delete, width);

      expect(tester.takeException(), isNull);
      final keys = tester.getRect(find.byType(AppShortcutKeys));
      final row = tester.getRect(find.byType(AppShortcutRow));
      expect(keys.right, lessThanOrEqualTo(row.right));
      // More than one line of 18-high caps: the later chords wrapped.
      expect(keys.height, greaterThan(18));
      // The name keeps a quarter of the row after the gap.
      expect(
        tester.getSize(find.byKey(labelKey)).width,
        greaterThanOrEqualTo((width - 10) * 0.25 - 0.5),
      );
    });
  }

  testWidgets('a short chord stays on one line and leaves the name the rest', (
    WidgetTester tester,
  ) async {
    await pumpRow(tester, AppShortcutIds.rename, 316);

    expect(tester.takeException(), isNull);
    final keys = tester.getSize(find.byType(AppShortcutKeys));
    expect(keys.height, 18);
    expect(tester.getSize(find.byKey(labelKey)).width, 316 - 10 - keys.width);
  });
}
