import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_icon_button.dart';

void main() {
  testWidgets('plain header action keeps size, tooltip, keyboard activation and disabled state', (
    tester,
  ) async {
    var presses = 0;
    Widget host(bool enabled) => MaterialApp(
      theme: buildAppTheme(accent: ThemeAccent.fromSeed(Colors.blue), brightness: Brightness.light),
      home: Scaffold(
        body: Center(
          child: AppIconButton(
            icon: Icons.history,
            tooltip: 'History',
            outlined: false,
            size: AppSize.compact,
            iconSize: AppSize.iconMd,
            onPressed: enabled ? () => presses++ : null,
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(true));
    expect(tester.getSize(find.byType(AppIconButton)), const Size.square(AppSize.compact));
    expect(find.byTooltip('History'), findsOneWidget);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect(shape.side, BorderSide.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
    await tester.pumpWidget(host(false));
    await tester.tap(find.byType(AppIconButton));
    expect(presses, 1);
  });
}
