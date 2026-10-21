import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/application_section.dart';
import 'package:joycai_image_ai_toolkits/services/llm/gpt_image_timeout.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dropdown.dart';
import 'package:provider/provider.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePrivateDataDir('gpt_timeout_settings');
  useRealAsyncAppState();
  setUpAll(() => AppState().loadSettings());

  for (final width in [390.0, 1440.0]) {
    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('timeout setting saves and reloads at $width in $locale', (tester) async {
        final state = AppState();
        await inRealAsync(tester, () => state.setGptImageTimeoutMinutes(25));
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpWidgetInRealAsync(
          tester,
          ChangeNotifierProvider.value(
            value: state,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: SingleChildScrollView(child: ApplicationSection())),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dropdown = find.byKey(const ValueKey('gpt-image-timeout'));
        expect(tester.widget<AppDropdown<int>>(dropdown).value, 25);
        await inRealAsync(tester, () => tester.tap(dropdown));
        await tester.pumpAndSettle();
        final label = lookupAppLocalizations(locale).gptImageTimeoutMinutes(45);
        await inRealAsyncUntil(
          tester,
          () => tester.tap(find.text(label).last),
          until: () => state.gptImageTimeoutMinutes == 45,
        );
        await tester.pumpAndSettle();
        await runAsyncRethrowing(tester, () async {
          expect(await state.getSetting(GptImageTimeout.settingKey), '45');
          state.gptImageTimeoutMinutes = 25;
          await state.loadSettings();
          expect(state.gptImageTimeoutMinutes, 45);
        });
        await tester.pump();
        expect(tester.widget<AppDropdown<int>>(dropdown).value, 45);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
