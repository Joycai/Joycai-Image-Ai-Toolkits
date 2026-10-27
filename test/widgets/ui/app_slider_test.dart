import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_slider.dart';

void main() {
  testWidgets('slider preserves keyboard steps, bounds, theme and disabled behavior', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var value = 6.0;
    var enabled = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          accent: ThemeAccent.fromSeed(Colors.blue),
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return AppSlider(
                value: value,
                min: 1,
                max: 15,
                divisions: 14,
                focusNode: focus,
                label: '${value.round()}s',
                onChanged: enabled ? (next) => setState(() => value = next) : null,
              );
            },
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, 7);
    rebuild(() => value = 15);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(value, 15);
    final context = tester.element(find.byType(Slider));
    expect(SliderTheme.of(context).activeTrackColor, Theme.of(context).colorScheme.primary);
    rebuild(() => enabled = false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.tap(find.byType(AppSlider));
    expect(value, 15);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });
}
