import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/context_window_slider.dart';

/// The context window's Specify slider (`D1c · 1a`): nine stops, a magnet,
/// tick labels that are buttons, ⇧-arrows that skip the minor stops.
///
/// Laid out 360 wide with the 20 inset, so the stops sit 40 apart from x = 20
/// to x = 340, and the magnet's ±3% of the track is ±9.6px.
void main() {
  Future<List<double>> pump(
    WidgetTester tester, {
    required double value,
    bool enabled = true,
  }) async {
    final changes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          accent: AppConstants.presetThemes.values.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: ContextWindowSlider(
                value: value,
                semanticLabel: 'probe',
                semanticValueOf: (v) => '$v',
                onChanged: enabled ? changes.add : null,
              ),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  Offset at(WidgetTester tester, double x) =>
      tester.getTopLeft(find.byType(ContextWindowSlider)) + Offset(x, 9);

  testWidgets('a tap within the magnet lands on the stop', (tester) async {
    final changes = await pump(tester, value: 0);
    await tester.tapAt(at(tester, 228)); // 8px right of the 128k stop at 220
    expect(changes, [5.0]);
  });

  testWidgets('a tap outside the magnet rests between stops, in proportion', (tester) async {
    final changes = await pump(tester, value: 0);
    await tester.tapAt(at(tester, 240)); // halfway from 128k (220) to 256k (260)
    expect(changes.single, closeTo(5.5, 1e-9));
  });

  testWidgets('a tick label is a button that goes straight to its stop', (tester) async {
    final changes = await pump(tester, value: 0);
    await tester.tap(find.text('256k'));
    await tester.tap(find.text('16k'));
    expect(changes, [6.0, 1.0]);
  });

  testWidgets('arrows walk every stop and shift-arrows only the major ones', (tester) async {
    final changes = await pump(tester, value: 2.5);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    // The widget holds 2.5 throughout (the test never feeds a change back),
    // so each key starts from between 32k and 64k: → 64k (3); ⇧→ skips 64k
    // for 96k (4); ⇧← lands on 32k (2), which is major.
    expect(changes, [3.0, 4.0, 2.0]);
  });

  testWidgets('greyed out, labels and taps do nothing', (tester) async {
    final changes = await pump(tester, value: 1, enabled: false);
    await tester.tapAt(at(tester, 300));
    await tester.tap(find.text('1M'), warnIfMissed: false);
    expect(changes, isEmpty);
  });

  testWidgets('the preset menu lists the nine stops and hands back the index picked', (
    tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          accent: AppConstants.presetThemes.values.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: Center(
            child: ContextWindowPresetMenu(
              label: 'Presets',
              selected: 5,
              onSelected: picked.add,
              height: 32,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Presets'));
    await tester.pumpAndSettle();
    expect(find.text('131,072'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('512k'));
    await tester.pumpAndSettle();
    expect(picked, [7]);
  });
}
