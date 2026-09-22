import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_draft.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_editor_fields.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_row.dart';

/// The request branch of the fee-group editor carries the 「输入图」 row
/// (`D2e · 24b`), and the fee-group card tags a request group that charges
/// inputs (`24d`) — the wiring the row and tag tests do not reach.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the editor shows the input row under request and spec, not under token', (tester) async {
    final draft = FeeGroupDraft(PricingGroup(id: 1, name: 'Relay', billingMode: 'request', requestPrice: 0.08));
    addTearDown(draft.dispose);
    await pump(tester, FeeGroupEditorFields(draft: draft));

    const price = ValueKey('spec-input-price');
    expect(find.byKey(price), findsOneWidget);
    expect(find.text('Input images'), findsOneWidget);
    // Under the request hint, not beside the request field.
    expect(
      tester.getTopLeft(find.byKey(price)).dy,
      greaterThan(tester.getBottomLeft(find.textContaining('Billed per successful request')).dy),
    );

    draft.setMode('token');
    await tester.pumpAndSettle();
    expect(find.byKey(price), findsNothing);

    draft.setMode('spec');
    await tester.pumpAndSettle();
    expect(find.byKey(price), findsOneWidget);
  });

  testWidgets('a request group that charges inputs gets the input tag on its card', (tester) async {
    final charging = PricingGroup(name: 'xAI video', billingMode: 'request', requestPrice: 0.08, inputUnitPrice: 0.01);
    final quiet = PricingGroup(name: 'Relay', billingMode: 'request', requestPrice: 0.04);
    await pump(
      tester,
      Builder(builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return Column(children: [
          Row(key: const ValueKey('charging'), children: feeGroupPriceTags(context, l10n, charging)),
          Row(key: const ValueKey('quiet'), children: feeGroupPriceTags(context, l10n, quiet)),
        ]);
      }),
    );

    expect(
      find.descendant(of: find.byKey(const ValueKey('charging')), matching: find.byType(FeePriceTag)),
      findsNWidgets(2),
    );
    expect(find.text('\$0.01/image'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('quiet')), matching: find.byType(FeePriceTag)),
      findsOneWidget,
    );
  });
}
