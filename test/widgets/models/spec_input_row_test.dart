import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/spec_rate_table.dart';

/// The 「输入图」 row under the rate table (`D2c · 22a–22d`): there for a
/// per-image group on every width, gone for the video units, and saying
/// what is wrong with what was typed without moving anything else.
void main() {
  const price = ValueKey('spec-input-price');
  const free = ValueKey('spec-input-free');

  Future<void> pump(
    WidgetTester tester, {
    OutputUnit unit = OutputUnit.image,
    bool narrow = false,
    double width = 460,
    bool invalid = false,
    bool freeOnly = false,
  }) async {
    final ctrls = [for (var i = 0; i < 3; i++) TextEditingController()];
    addTearDown(() {
      for (final c in ctrls) {
        c.dispose();
      }
    });
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SpecRateTableEditor(
            unit: unit,
            onUnitChanged: (_) {},
            rows: const [],
            otherPriceCtrl: ctrls[0],
            inputPriceCtrl: ctrls[1],
            inputFreeCtrl: ctrls[2],
            inputPriceInvalid: invalid,
            inputFreeWithoutPrice: freeOnly,
            onAddRow: () {},
            onRemoveRow: (_) {},
            onChanged: () {},
            onSwitchToRequest: () {},
            narrow: narrow,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final (name, narrow, width) in [('wide', false, 460.0), ('narrow', true, 390.0)]) {
    testWidgets('a per-image table ends in the input row ($name), without overflow', (tester) async {
      await pump(tester, narrow: narrow, width: width);

      expect(tester.takeException(), isNull);
      expect(find.text('Input images'), findsOneWidget);
      expect(find.byKey(price), findsOneWidget);
      expect(find.byKey(free), findsOneWidget);
      // Under the priority rule: the D2b block above it is untouched.
      expect(
        tester.getTopLeft(find.text('Input images')).dy,
        greaterThan(tester.getTopLeft(find.textContaining('Blank means "any"')).dy),
      );
      // Blank by default, and quiet: no hint until something is wrong.
      expect(find.textContaining('free count'), findsNothing);
    });
  }

  testWidgets('the wide price field sits on the same vertical as the catch-all\'s', (tester) async {
    await pump(tester);
    final other = find.widgetWithText(TextField, '0.0000').first;
    expect(tester.getTopLeft(find.byKey(price)).dx, tester.getTopLeft(other).dx);
    expect(tester.getSize(find.byKey(price)).width, tester.getSize(other).width);
  });

  testWidgets('per second and per clip have no input row at all', (tester) async {
    for (final unit in [OutputUnit.second, OutputUnit.clip]) {
      await pump(tester, unit: unit);
      expect(find.text('Input images'), findsNothing, reason: unit.name);
      expect(find.byKey(price), findsNothing, reason: unit.name);
    }
  });

  testWidgets('the free count takes digits only, two of them', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(free), '1.5x27');
    expect(tester.widget<TextField>(find.descendant(of: find.byKey(free), matching: find.byType(TextField)))
        .controller!.text, '15');
  });

  testWidgets('a free count with no price is explained; a bad price is an error', (tester) async {
    await pump(tester, freeOnly: true);
    expect(find.textContaining('Only a free count is set'), findsOneWidget);

    await pump(tester, invalid: true, freeOnly: true);
    expect(find.textContaining('not a valid non-negative number'), findsOneWidget);
    expect(find.textContaining('Only a free count is set'), findsNothing, reason: 'one line, the error first');
  });
}
