import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_dropdown.dart';

void main() {
  const seed = Colors.indigo;

  Widget host(Widget child) => MaterialApp(
        theme: buildAppTheme(seedColor: seed, brightness: Brightness.light),
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
}
