import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_wizard_dialog.dart';

Future<void> _pumpWizard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return Scaffold(
            body: ChannelWizardDialog(l10n: l10n, appState: AppState()),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

/// Move to step 2 with whichever provider card is currently selected.
Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

void main() {
  // Two regressions, both of which shipped: provider cards that existed in the
  // preset list but were never rendered, and an endpoint the user could not
  // edit once a preset supplied one.

  testWidgets('every provider preset is reachable on step 1', (tester) async {
    await _pumpWizard(tester);

    // Names that only appear as provider cards. DashScope and Qianwen are the
    // ones that went missing; the other two disappeared the same way earlier.
    for (final label in const [
      'DeepSeek',
      'MiniMax',
      'Alibaba DashScope',
      'Qianwen Platform',
    ]) {
      expect(
        find.text(label),
        findsWidgets,
        reason: '$label is defined as a preset but not rendered on step 1',
      );
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('preset endpoint is prefilled and still editable',
      (tester) async {
    await _pumpWizard(tester);

    await tester.tap(find.text('Qianwen Platform'));
    await tester.pumpAndSettle();
    await _tapNext(tester);

    final field = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(field).controller?.text,
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
      reason: 'the preset should prefill its host',
    );

    // The international host is the case that has no preset of its own and so
    // is only reachable by typing over the suggestion.
    const intl = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';
    await tester.enterText(field, intl);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text, intl);

    expect(tester.takeException(), isNull);
  });

  testWidgets('switching provider replaces the previous host', (tester) async {
    await _pumpWizard(tester);

    await tester.tap(find.text('Qianwen Platform'));
    await tester.pumpAndSettle();
    await _tapNext(tester);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    await _tapNext(tester);

    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'https://api.deepseek.com',
      reason: 'a stale host here would create a channel pointed at Qianwen',
    );
  });
}
