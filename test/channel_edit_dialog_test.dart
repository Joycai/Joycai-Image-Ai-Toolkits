import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_edit_dialog.dart';

LLMChannel _sampleChannel() => LLMChannel(
      id: 1,
      displayName: 'YYDS-Google',
      endpoint: 'https://example.com/v1beta',
      apiKey: 'sk-test',
      type: 'google-genai-rest',
      enableDiscovery: true,
      tag: 'google',
      tagColor: 0xFF2196F3,
    );

Future<void> _pumpDialog(WidgetTester tester) async {
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
              channel: _sampleChannel(),
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
}
