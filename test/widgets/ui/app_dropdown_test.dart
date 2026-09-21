import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dropdown.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_field_size.dart';
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

  // The shape of the one real caller — the model editor's fee-group field:
  // large, with a prefix icon — at a 390pt phone page, a 320pt device, and
  // narrower still.
  for (final width in [366.0, 296.0, 240.0]) {
    testWidgets('a long trailing yields to the label and never overflows @ $width', (tester) async {
      // A fee group's one-line summary rides here, and an input-image rate
      // about doubled it (`D2c`).
      const summary = 'Per image · 1 rates · \$0.30–0.30 · input \$0.02/image · first 1 free';
      await tester.pumpWidget(host(SizedBox(
        width: width,
        child: AppDropdown<int>(
          value: 1,
          size: AppFieldSize.large,
          prefixIcon: Icons.payments_outlined,
          items: const [
            AppDropdownItem(value: 1, label: 'Seedream 5.0 pro', trailing: summary),
            AppDropdownItem(value: 2, label: 'Another group', trailing: summary),
          ],
          onChanged: (_) {},
        ),
      )));
      await tester.tap(find.byType(AppDropdown<int>));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final label = tester.getSize(find.text('Another group').last).width;
      final trailing = tester.getSize(find.text(summary).last).width;
      expect(label, greaterThan(trailing), reason: 'the name is what is being chosen');
      expect(trailing, lessThanOrEqualTo(200));
    });
  }

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
