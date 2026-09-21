import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_controls.dart';

/// The model editor's stop slider (`D1c`): stops at equal distances, a value
/// in stop units, snapping for a ladder and resting between stops for a scale.
///
/// Laid out 248 wide with the default 24 inset, so the five stops below sit at
/// x = 24, 74, 124, 174 and 224.
void main() {
  Future<List<double>> pump(
    WidgetTester tester, {
    required double value,
    bool snap = false,
    bool enabled = true,
  }) async {
    final changes = <double>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(
        accent: AppConstants.presetThemes.values.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 248,
            child: ModelEditTrackSlider(
              stopCount: 5,
              value: value,
              snap: snap,
              labels: const ['a', null, 'c', null, 'e'],
              semanticLabel: 'probe',
              semanticValueOf: (v) => '$v',
              onChanged: enabled ? changes.add : null,
            ),
          ),
        ),
      ),
    ));
    return changes;
  }

  Offset at(WidgetTester tester, double x) {
    final box = tester.getTopLeft(find.byType(ModelEditTrackSlider));
    return box + Offset(x, 9);
  }

  testWidgets('a tap on a stop lands on that stop', (tester) async {
    final changes = await pump(tester, value: 0, snap: true);
    await tester.tapAt(at(tester, 174));
    expect(changes, [3.0]);
  });

  testWidgets('a snapping slider rounds a tap between stops to the nearer one', (tester) async {
    final changes = await pump(tester, value: 0, snap: true);
    await tester.tapAt(at(tester, 110));
    expect(changes, [2.0]);
  });

  testWidgets('a scale rests between stops, in proportion', (tester) async {
    final changes = await pump(tester, value: 0);
    await tester.tapAt(at(tester, 99));
    expect(changes.single, closeTo(1.5, 1e-9));
  });

  testWidgets('taps past either end clamp to the first and last stop', (tester) async {
    final changes = await pump(tester, value: 2, snap: true);
    await tester.tapAt(at(tester, 2));
    await tester.tapAt(at(tester, 246));
    expect(changes, [0.0, 4.0]);
  });

  testWidgets('arrow keys go to the neighbouring stop, also from between two', (tester) async {
    final changes = await pump(tester, value: 1.5);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(changes, [2.0, 1.0]);
  });

  testWidgets('greyed out, it ignores taps and keys and says so to assistive tech', (tester) async {
    final handle = tester.ensureSemantics();
    final changes = await pump(tester, value: 1, snap: true, enabled: false);
    await tester.tapAt(at(tester, 224));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(changes, isEmpty);
    expect(
      tester.getSemantics(find.byType(ModelEditTrackSlider)),
      isSemantics(isSlider: true, hasEnabledState: true, isEnabled: false),
    );
    handle.dispose();
  });
}
