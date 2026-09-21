import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dropdown.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';

void main() {
  const seed = Colors.indigo;

  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(accent: ThemeAccent.fromSeed(seed), brightness: Brightness.light),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('selecting an item reports its value through onChanged', (tester) async {
    int? selected;
    await tester.pumpWidget(host(AppDropdown<int>(
      value: 1,
      items: const [
        AppDropdownItem(value: 1, label: 'One'),
        AppDropdownItem(value: 2, label: 'Two'),
      ],
      onChanged: (v) => selected = v,
    )));

    await tester.tap(find.byType(AppDropdown<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two').last);
    await tester.pumpAndSettle();

    expect(selected, 2);
  });

  testWidgets('enabled: false disables onChanged', (tester) async {
    await tester.pumpWidget(host(AppDropdown<int>(
      value: 1,
      items: const [AppDropdownItem(value: 1, label: 'One')],
      onChanged: (_) {},
      enabled: false,
    )));

    expect(tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).onChanged, isNull);
  });

  testWidgets('the open menu checks the current value, and the field does not', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 240,
      child: AppDropdown<int>(
        value: 2,
        items: const [
          AppDropdownItem(value: 1, label: 'One'),
          AppDropdownItem(value: 2, label: 'Two'),
        ],
        onChanged: (_) {},
      ),
    )));
    expect(find.byIcon(Icons.check), findsNothing, reason: 'the closed field carries no check');

    await tester.tap(find.byType(AppDropdown<int>));
    await tester.pumpAndSettle();
    final check = find.byIcon(Icons.check);
    expect(check, findsOneWidget);
    // On the row that says Two.
    final row = find.ancestor(of: check, matching: find.byType(Row)).first;
    expect(find.descendant(of: row, matching: find.text('Two')), findsOneWidget);
    await tester.tap(find.text('Two').last);
    await tester.pumpAndSettle();
  });
}
