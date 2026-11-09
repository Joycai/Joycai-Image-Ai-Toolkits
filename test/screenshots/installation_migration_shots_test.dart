@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_paths.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/installation_migration_screen.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/setup_wizard.dart';
import 'package:joycai_image_ai_toolkits/services/files/installation_migration_service.dart';
import 'package:joycai_image_ai_toolkits/state/installation_migration_state.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      for (final locale in AppLocalizations.supportedLocales) {
        testWidgets('installation ${size.label} ${brightness.name} $locale', (tester) async {
          final state = InstallationMigrationState()
            ..source = '/Users/artist/Library/Application Support/cn.joycai.joycaiImageAiToolkits'
            ..acknowledged = true;
          await _migrationShot(tester, state, size, brightness, locale, 'selected');
          state.dispose();
        });
      }
      testWidgets('migration setting ${size.label} ${brightness.name}', (tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.settings,
          size: size,
          brightness: brightness,
          suffix: 'installationEntry',
          after: (tester) async {
            final l10n = lookupAppLocalizations(const Locale('zh'));
            await actInRealAsync(tester, () => tester.tap(find.text(l10n.application).first));
            if (AppPaths.supportsInstallationImport) {
              await tester.ensureVisible(find.text(l10n.installationImportSchedule).last);
            }
            await settle(tester, 6);
          },
        );
      });
      testWidgets('storage wizard ${size.label} ${brightness.name}', (tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.settings,
          size: size,
          brightness: brightness,
          suffix: 'storageWizard',
          after: (tester) async {
            await actInRealAsync(tester, () async {
              final context = tester.element(find.byType(Navigator).first);
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const SetupWizard()));
            });
            await tester.tap(find.text('下一步'));
            await settle(tester, 6);
          },
        );
      });
    }
  }
  for (final variant in ['initial', 'busy', 'error', 'success']) {
    for (final brightness in Brightness.values) {
      testWidgets('migration $variant ${brightness.name}', (tester) async {
        final state = InstallationMigrationState();
        if (variant != 'initial') state.source = '/Users/artist/old-data';
        if (variant == 'busy') state.busy = true;
        if (variant == 'error') state.error = InstallationMigrationError.sourceChanged;
        if (variant == 'success') {
          state.imported = true;
          state.destination = '/Users/artist/Library/Containers/cn.joycai.joycaiImageAiToolkits/Data/Library/Application Support/cn.joycai.joycaiImageAiToolkits/installations/12345678-1234-1234-1234-123456789abc';
        }
        await _migrationShot(
          tester,
          state,
          kShotSizes.first,
          brightness,
          const Locale('zh'),
          variant,
        );
        state.dispose();
      });
    }
  }
}

Future<void> _migrationShot(
  WidgetTester tester,
  InstallationMigrationState state,
  ShotSize size,
  Brightness brightness,
  Locale locale,
  String variant,
) async {
  tester.view.physicalSize = size.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(
        accent: AppConstants.presetThemes.values.first,
        brightness: brightness,
        fontFamily: 'NotoSansSC',
      ),
      home: InstallationMigrationScreen(state: state, onContinue: () {}),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
      'installation_${size.label}_${brightness.name}_${locale.toLanguageTag()}_$variant.png',
    ),
  );
  await tester.pumpWidget(const SizedBox.shrink());
}
