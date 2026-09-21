import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/spec_rate_table.dart';

/// "Only the Other row = the same as Per request" holds for a per-clip table
/// alone. Per image counts every picture a request returned (a group of four
/// is four units) and per second the length, while Per request counts the
/// call once — so for those units the hint, and its switch button, were a
/// wrong promise.
void main() {
  Future<void> pump(WidgetTester tester, OutputUnit unit) async {
    final other = TextEditingController(text: '0.1');
    addTearDown(other.dispose);
    final inputPrice = TextEditingController();
    final inputFree = TextEditingController();
    addTearDown(inputPrice.dispose);
    addTearDown(inputFree.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SpecRateTableEditor(
            unit: unit,
            onUnitChanged: (_) {},
            rows: const [],
            otherPriceCtrl: other,
            inputPriceCtrl: inputPrice,
            inputFreeCtrl: inputFree,
            inputPriceInvalid: false,
            inputFreeWithoutPrice: false,
            onAddRow: () {},
            onRemoveRow: (_) {},
            onChanged: () {},
            onSwitchToRequest: () {},
            narrow: false,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  const hint = 'works the same as Per request';

  testWidgets('a per-clip table with only Other offers the switch', (tester) async {
    await pump(tester, OutputUnit.clip);
    expect(find.textContaining(hint), findsOneWidget);
  });

  for (final unit in [OutputUnit.image, OutputUnit.second]) {
    testWidgets('a per-${unit.name} table does not claim it', (tester) async {
      await pump(tester, unit);
      expect(find.textContaining(hint), findsNothing);
    });
  }
}
