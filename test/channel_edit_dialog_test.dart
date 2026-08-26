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

  testWidgets('the protocol field offers every family', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDialog(tester);

    final offered = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .expand((d) => d.items ?? const <DropdownMenuItem<String>>[])
        .map((item) => item.value)
        .toSet();

    // The field names wire formats now, not suppliers — the supplier lives in
    // the preset bar above it. Every family has to be reachable.
    for (final family in ProtocolFamily.values) {
      expect(
        offered,
        contains(genericVendorForFamily(family)),
        reason: '${family.name} cannot be chosen as a protocol',
      );
    }
  });

  testWidgets('a supplier-specific type is representable alongside them',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // dashscope-api is not a generic family profile, so it only opens if
    // the field lists the stored type itself. This is the exact shape of the
    // bug that made a DashScope channel impossible to edit.
    await _pumpDialog(tester, type: Vendors.dashscope);

    final offered = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .expand((d) => d.items ?? const <DropdownMenuItem<String>>[])
        .map((item) => item.value)
        .toSet();
    expect(offered, contains(Vendors.dashscope));
    expect(tester.takeException(), isNull);
  });

  // The shortcut bar: which preset this channel sits on, or an honest "none"
  // for a type created by an older build.
  group('provider preset bar', () {
    testWidgets('names the preset a stored type came from', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await _pumpDialog(tester, type: Vendors.dashscope);

      expect(find.text('Provider preset'), findsOneWidget);
      // The chip names the supplier — and, since DashScope's two faces are
      // two presets, which face this channel is on comes with the name. The
      // protocol field below names the wire format that face speaks.
      expect(find.text('Alibaba DashScope (OpenAI compatible)'),
          findsOneWidget);
      expect(
        find.text('OpenAI · chat/completions · '
            'Alibaba DashScope (OpenAI compatible)'),
        findsOneWidget,
      );
      expect(find.text('Change preset'), findsWidgets);
    });

    testWidgets('names the variant when the preset has more than one',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await _pumpDialog(tester, type: Vendors.newApiGemini);

      expect(find.text('NewAPI · Gemini format'), findsOneWidget);
    });

    testWidgets('says so when no preset matches, and still opens',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // The deprecated type: no preset offers it, and it must neither be
      // rewritten nor block the dialog.
      await _pumpDialog(tester, type: Vendors.officialGoogle);

      expect(find.text('No matching preset'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // The shortcut itself: it fills the fields and leaves the user's own
  // values alone. The list it opens is the add-channel catalogue, which is
  // the structural half of the fix — one list, so neither dialog can drift.
  testWidgets('changing preset rewrites protocol and address, keeps the key',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDialog(tester, type: Vendors.dashscope);

    await tester.tap(find.text('Change preset').first);
    await tester.pumpAndSettle();
    expect(find.text('DeepSeek'), findsWidgets);

    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();

    // The preset supplied the protocol and the address...
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(
      find.textContaining('api.deepseek.com'),
      findsWidgets,
      reason: "the preset's endpoint should have been applied",
    );
    // ...and left the key, name and tag as the user had them.
    expect(find.text('YYDS-Google'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a local runtime marks its key optional', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpDialog(tester, type: Vendors.ollama);

    expect(find.textContaining('Optional'), findsWidgets);
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
