import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/setup_wizard.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/api_key_field.dart';
import 'package:provider/provider.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

/// The setup wizard's channel and model steps write through [AppState], so
/// what they create is in the model cache the moment the wizard closes.
///
/// They used to write to the database directly: the rows were there, but
/// `AppState.allChannels` and `allModels` — what the models page and the
/// workbench's picker read — stayed empty until something else refreshed the
/// cache, or the app was restarted. First run is exactly this path.
void main() {
  usePrivateDataDir('joycai_setup_wizard_test');
  useRealAsyncAppState();

  late AppLocalizations l10n;
  late Directory outputDir;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    outputDir = Directory.systemTemp.createTempSync('joycai_wizard_out');
    // The storage step's Next is disabled until an output directory is set,
    // and the wizard pre-fills its field from the gallery's.
    await AppState().updateOutputDirectory(outputDir.path);
  });

  tearDownAll(() => outputDir.deleteSync(recursive: true));

  Future<void> pumpWizard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final appState = AppState();
    await pumpWidgetInRealAsync(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: appState.galleryState),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SetupWizard(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder next() => find.text(l10n.next);

  Finder textFieldWithHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
    description: 'TextField hinting "$hint"',
  );

  testWidgets('a channel and a model created in the wizard reach AppState', (tester) async {
    final appState = AppState();
    final before = appState.allChannels.length;
    await pumpWizard(tester);

    // Welcome → storage → channel.
    await tester.tap(next());
    await tester.pumpAndSettle();
    await tester.tap(next());
    await tester.pumpAndSettle();

    await tester.enterText(textFieldWithHint('e.g. My OpenAI'), 'Wizard Channel');
    await tester.enterText(
      find.descendant(of: find.byType(ApiKeyField), matching: find.byType(TextField)),
      'sk-test',
    );
    await tester.pump();

    // Next on the channel step writes the channel, then turns the page.
    await inRealAsyncUntil(
      tester,
      () => tester.tap(next()),
      until: () => appState.allChannels.any((c) => c.displayName == 'Wizard Channel'),
    );
    await tester.pumpAndSettle();
    expect(appState.allChannels.length, before + 1);
    final channel = appState.allChannels.firstWhere((c) => c.displayName == 'Wizard Channel');

    await tester.enterText(textFieldWithHint('e.g. gpt-4o'), 'gemini-3-pro');
    await tester.pump();
    await inRealAsyncUntil(
      tester,
      () => tester.tap(next()),
      until: () => appState.allModels.any((m) => m.modelId == 'gemini-3-pro'),
    );
    await tester.pumpAndSettle();

    final model = appState.allModels.firstWhere((m) => m.modelId == 'gemini-3-pro');
    expect(model.channelId, channel.id);
    expect(model.modelName, 'gemini-3-pro', reason: 'an empty display name falls back to the id');
    expect(find.text(l10n.getStarted), findsOneWidget);
  });
}
