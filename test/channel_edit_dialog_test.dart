import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_edit_dialog.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';

LLMChannel _sampleChannel({String type = 'google-genai-rest'}) => LLMChannel(
      id: 1,
      displayName: 'YYDS-Google',
      endpoint: 'https://example.com/v1beta',
      apiKey: 'sk-test',
      type: type,
      enableDiscovery: true,
      tag: 'google',
      tagColor: 0xFF2196F3,
    );

Future<void> _pumpDialog(WidgetTester tester, {String type = 'google-genai-rest'}) async {
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
            body: ChannelEditDialog(
              l10n: l10n,
              appState: AppState(),
              channel: _sampleChannel(type: type),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // Regression: editing an existing channel used to crash with
  // "LayoutBuilder does not support returning intrinsic dimensions" because
  // AlertDialog's IntrinsicWidth recursed into a LayoutBuilder. The dialog must
  // build cleanly on both desktop (AlertDialog) and mobile (Scaffold) layouts.

  testWidgets('builds for existing channel on desktop', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDialog(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('builds for existing channel on mobile', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDialog(tester);

    expect(tester.takeException(), isNull);
  });

  // Regression: the channel-type dropdown was a hand-written list and had gone
  // stale — DashScope was offered by the add-channel wizard but missing here,
  // and Material asserts that a dropdown's value is one of its items, so an
  // existing DashScope channel could not be opened for editing at all. The
  // list is now derived from the vendor registry; these pin that it stays so.

  testWidgets('the type dropdown names every vendor', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDialog(tester);

    final offered = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .expand((d) => d.items ?? const <DropdownMenuItem<String>>[])
        .map((item) => item.value)
        .toSet();

    for (final vendor in Vendors.all) {
      expect(
        offered,
        contains(vendor.id),
        reason: '${vendor.id} is a storable channel type the editor cannot show',
      );
    }
  });

  testWidgets('every vendor is also named, not left as a raw id',
      (tester) async {
    await _pumpDialog(tester);
    final BuildContext context = tester.element(find.byType(ChannelEditDialog));
    final l10n = AppLocalizations.of(context)!;

    for (final vendor in Vendors.all) {
      expect(
        channelTypeLabel(l10n, vendor.id),
        isNot(vendor.id),
        reason: '${vendor.id} falls through to the unknown-type default',
      );
    }
  });

  for (final vendor in Vendors.all) {
    testWidgets('opens a ${vendor.id} channel for editing', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await _pumpDialog(tester, type: vendor.id);

      expect(tester.takeException(), isNull);
    });
  }
}
