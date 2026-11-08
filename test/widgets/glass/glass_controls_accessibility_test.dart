import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/glass_controls.dart';

void main() {
  for (final labels in [true, false]) {
    testWidgets('glass segments have one name and keyboard selection ($labels)', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        var value = 0;
        var calls = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => GlassSegmented<int>(
                  showLabels: labels,
                  segments: const [
                    GlassSegment(value: 0, label: 'Image', icon: Icons.image),
                    GlassSegment(value: 1, label: 'Video', icon: Icons.movie),
                  ],
                  value: value,
                  onChanged: (next) => setState(() {
                    value = next;
                    calls++;
                  }),
                ),
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel('Image'), findsOneWidget);
        expect(find.bySemanticsLabel('Video'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(calls, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(value, 1);
        expect(calls, 1);
        final node = tester.getSemantics(find.bySemanticsLabel('Video'));
        expect(node.flagsCollection.isSelected, Tristate.isTrue);
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(calls, 1);
      } finally {
        handle.dispose();
      }
    });
  }

  testWidgets('glass actions skip disabled buttons and activate once', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                GlassIconButton(
                  icon: Icons.save,
                  label: 'Save',
                  tooltip: 'Save',
                  onPressed: () => calls++,
                ),
                const GlassIconButton(icon: Icons.block, tooltip: 'Disabled', onPressed: null),
                GlassFab(icon: Icons.add, tooltip: 'Add', onPressed: () => calls += 10),
              ],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Save'), findsOneWidget);
      final disabled = tester.getSemantics(find.bySemanticsLabel('Disabled')).getSemanticsData();
      expect(disabled.hasAction(SemanticsAction.tap), isFalse);
      expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls, 11);
    } finally {
      handle.dispose();
    }
  });
}
