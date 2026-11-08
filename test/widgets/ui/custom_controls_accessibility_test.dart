import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_icon_button.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_setting_row.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_switch.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/color_hue_picker.dart';

Widget host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 400, child: child)),
  ),
);

void main() {
  testWidgets('icon action exposes its name, selected state and activation on one node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      var calls = 0;
      await tester.pumpWidget(
        host(
          AppIconButton(
            icon: Icons.star,
            tooltip: 'Favorite',
            selected: true,
            onPressed: () => calls++,
          ),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Favorite'));
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.getSemanticsData().tooltip, isEmpty);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
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
  for (final row in [false, true]) {
    testWidgets('setting switch merges name and keeps footer separate ($row)', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        var value = false;
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) {
                void change(bool next) => setState(() => value = next);
                return row
                    ? AppSettingRow(
                        title: 'Notifications',
                        description: 'Show completed tasks',
                        trailing: AppSwitch(value: value, onChanged: change),
                        footer: TextButton(onPressed: () {}, child: const Text('Details')),
                      )
                    : AppToggleRow(
                        title: 'Notifications',
                        description: 'Show completed tasks',
                        value: value,
                        onChanged: change,
                      );
              },
            ),
          ),
        );
        final target = find.bySemanticsLabel('Notifications\nShow completed tasks');
        expect(target, findsOneWidget);
        final node = tester.getSemantics(target);
        expect(node.flagsCollection.isToggled, Tristate.isFalse);
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.tap,
        );
        await tester.pumpAndSettle();
        expect(value, isTrue);
        if (row) expect(find.bySemanticsLabel('Details'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(value, isFalse);
      } finally {
        handle.dispose();
      }
    });
  }

  for (final wheel in [true, false]) {
    testWidgets('hue surface supports keyboard and semantic adjustment ($wheel)', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        var color = const Color(0xffe62e2e);
        await tester.pumpWidget(
          host(
            StatefulBuilder(
              builder: (context, setState) {
                void change(int next) => setState(() => color = Color(next));
                return wheel
                    ? ColorHuePicker(initialColor: color, onColorChanged: change)
                    : ColorHueBar(color: color, onColorChanged: change);
              },
            ),
          ),
        );
        final finder = find.bySemanticsLabel('Custom color');
        expect(finder, findsOneWidget);
        final node = tester.getSemantics(finder);
        expect(node.flagsCollection.isSlider, isTrue);
        tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          SemanticsAction.increase,
        );
        await tester.pumpAndSettle();
        expect(HSVColor.fromColor(color).hue, closeTo(5, 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(HSVColor.fromColor(color).hue, closeTo(0, 1));
      } finally {
        handle.dispose();
      }
    });
  }
}
