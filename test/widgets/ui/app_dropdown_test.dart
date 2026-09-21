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
  // large, with a prefix icon, and a first item that has no trailing.
  group('a rich item\'s trailing', () {
    const long = 'Per image · 1 rates · \$0.30–0.30 · input \$0.02/image · first 1 free';
    const short = '\$0.04/req';

    Future<void> open(WidgetTester tester, double width, String label, String trailing) async {
      await tester.pumpWidget(host(SizedBox(
        width: width,
        child: AppDropdown<int>(
          value: 0,
          size: AppFieldSize.large,
          prefixIcon: Icons.payments_outlined,
          items: [
            const AppDropdownItem(value: 0, label: 'No fee group', muted: true),
            AppDropdownItem(value: 1, label: label, trailing: trailing),
          ],
          onChanged: (_) {},
        ),
      )));
      await tester.tap(find.byType(AppDropdown<int>));
      await tester.pumpAndSettle();
    }

    /// The row the item lays out in, and the boxes of its two ends.
    ({Rect row, Rect label, Rect trailing}) boxes(WidgetTester tester, String label, String trailing) {
      final trailingText = find.text(trailing).last;
      final row = find.ancestor(of: trailingText, matching: find.byType(Row)).first;
      final labelBox = find.ancestor(of: find.text(label).last, matching: find.byType(Expanded)).first;
      return (row: tester.getRect(row), label: tester.getRect(labelBox), trailing: tester.getRect(trailingText));
    }

    // A 390pt phone page, a 320pt device, and narrower still.
    for (final width in [366.0, 296.0, 240.0]) {
      testWidgets('a long one is cut at its share and the name keeps the rest @ $width', (tester) async {
        await open(tester, width, 'Gemini 2.5 Pro Long Context Tier', long);

        expect(tester.takeException(), isNull);
        final b = boxes(tester, 'Gemini 2.5 Pro Long Context Tier', long);
        expect(b.trailing.width, closeTo(b.row.width * 0.4, 0.5), reason: 'cut at 40% of the row');
        expect(b.label.width, greaterThan(b.row.width * 0.5), reason: 'the name is what is being chosen');
        expect(b.trailing.right, closeTo(b.row.right, 0.5));
      });
    }

    testWidgets('a short one is shown whole, flush right, and takes nothing it does not need', (tester) async {
      await open(tester, 422, 'Flux', short);

      final b = boxes(tester, 'Flux', short);
      final intrinsic = (tester.renderObject(find.text(short).last) as RenderBox).getMaxIntrinsicWidth(double.infinity);
      expect(b.trailing.width, closeTo(intrinsic, 0.5), reason: 'not cut');
      expect(b.trailing.right, closeTo(b.row.right, 0.5), reason: 'no dead space after it');
      expect(b.label.right, closeTo(b.trailing.left - 12, 0.5), reason: 'the label box has all that is left');
    });

    testWidgets('a cut one ends on the row\'s right edge, not short of it', (tester) async {
      await open(tester, 366, 'Seedream 5.0 pro', long);
      expect(tester.widget<Text>(find.text(long).last).textAlign, TextAlign.end);
    });

    testWidgets('the closed field never builds the menu row, whichever item is selected', (tester) async {
      // The LayoutBuilder is safe because it lives in the menu route alone:
      // the button shows `selectedItemBuilder`'s plain label. In the button
      // it would sit in an IndexedStack, and throw under any ancestor that
      // measures intrinsics.
      await tester.pumpWidget(host(IntrinsicWidth(
        child: AppDropdown<int>(
          value: 1,
          items: const [
            AppDropdownItem(value: 0, label: 'No fee group'),
            AppDropdownItem(value: 1, label: 'Seedream 5.0 pro', trailing: long, description: 'spec'),
          ],
          onChanged: (_) {},
        ),
      )));

      expect(tester.takeException(), isNull);
      expect(find.text('Seedream 5.0 pro'), findsOneWidget);
      expect(find.text(long), findsNothing);
      expect(find.descendant(of: find.byType(AppDropdown<int>), matching: find.byType(LayoutBuilder)), findsNothing);
    });

    testWidgets('on a wide row the cap is 200, not the share', (tester) async {
      await open(tester, 720, 'Seedream 5.0 pro', '$long · $long');

      expect(tester.takeException(), isNull);
      expect(boxes(tester, 'Seedream 5.0 pro', '$long · $long').trailing.width, closeTo(200, 0.5));
    });
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
