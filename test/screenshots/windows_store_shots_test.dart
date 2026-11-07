@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/credential_recovery_screen.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/installation_migration_screen.dart';
import 'package:joycai_image_ai_toolkits/state/installation_migration_state.dart';

import 'harness/shoot.dart';

void main() {
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      for (final locale in AppLocalizations.supportedLocales) {
        for (final recovery in [true, false]) {
          final name =
              'windows_${recovery ? 'recovery' : 'import'}_${size.label}_${brightness.name}_$locale';
          testWidgets(name, (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = size.size;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final state = InstallationMigrationState()
              ..source = r'C:\Users\Artist\AppData\Roaming\Joycai\Joycai Image AI Toolkits'
              ..acknowledged = true;
            await tester.pumpWidget(
              MaterialApp(
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildAppTheme(
                  accent: AppConstants.presetThemes.values.first,
                  brightness: brightness,
                  fontFamily: 'NotoSansSC',
                ),
                home: recovery
                    ? CredentialRecoveryScreen(onRetry: () async {}, onReset: () async {})
                    : InstallationMigrationScreen(state: state, onContinue: () {}, windows: true),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile('../../build/ui-screenshots/$name.png'),
            );
            await tester.pumpWidget(const SizedBox.shrink());
            state.dispose();
          });
        }
      }
    }
  }
}
