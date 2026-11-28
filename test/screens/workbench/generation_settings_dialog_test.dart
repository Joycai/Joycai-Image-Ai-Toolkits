import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/config/generation_settings_dialog.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  usePrivateDataDir('joycai_generation_settings_dialog_test');
  useRealAsyncAppState();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('toggling saveGenerationText persists through AppState', (tester) async {
    final appState = AppState();
    await inRealAsync(tester, () => appState.setSaveGenerationText(false));

    await pumpWidgetInRealAsync(
      tester,
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => unawaited(showGenerationSettingsDialog(context)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final toggle = find.descendant(
      of: find.byKey(const ValueKey('save_generation_text_row')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(toggle);
    await inRealAsyncUntil(
      tester,
      () => tester.tap(toggle),
      until: () => appState.saveGenerationText,
    );

    expect(appState.saveGenerationText, isTrue);
    await runAsyncRethrowing(tester, () async {
      expect(await appState.getSetting('save_generation_text'), 'true');
    });
  });
}
