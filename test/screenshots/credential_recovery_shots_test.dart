@Tags(['screenshots'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_distribution.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/credential_recovery_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'harness/shoot.dart';

void main() {
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      for (final locale in [
        const Locale('zh'),
        const Locale('en'),
        const Locale('ja'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]) {
        const variant = AppDistribution.direct ? 'direct' : 'signed';
        final name =
            'credential_recovery_${variant}_${size.label}_${brightness.name}_${locale.toString()}';
        testWidgets(name, (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size.size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildAppTheme(
                accent: AppConstants.presetThemes.values.first,
                brightness: brightness,
                fontFamily: 'NotoSansSC',
              ),
              home: CredentialRecoveryScreen(
                requiresSignedMacBuild: AppDistribution.direct,
                onRetry: () async {},
                onReset: AppDistribution.direct ? null : () async {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
            debugPrint('[$name] exception during pump: $e');
          }
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../../build/ui-screenshots/$name.png'),
          );
        });
      }
    }
  }
}
