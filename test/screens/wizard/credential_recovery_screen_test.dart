import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/credential_recovery_screen.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/installation_migration_screen.dart';
import 'package:joycai_image_ai_toolkits/state/installation_migration_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/real_fonts.dart';

void main() {
  setUpAll(() async {
    await ensureRealTestFontsLoaded();
  });
  testWidgets('direct Mac recovery explains signature mismatch without offering data reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CredentialRecoveryScreen(requiresSignedMacBuild: true, onRetry: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Full Disk Access does not grant Keychain access'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(AppButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows credential reset requires explicit consent and stays serialized', (
    tester,
  ) async {
    final attempt = Completer<void>();
    var resets = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CredentialRecoveryScreen(
          isWindows: true,
          onRetry: () async {},
          onReset: () {
            resets++;
            return attempt.future;
          },
        ),
      ),
    );
    final reset = find.widgetWithText(AppButton, 'Clear credentials and continue');
    expect(tester.widget<AppButton>(reset).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(resets, 1);
    expect(tester.widget<AppButton>(reset).onPressed, isNull);
    attempt.completeError(StateError('private details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private details'), findsNothing);
    expect(tester.widget<AppButton>(reset).onPressed, isNotNull);
  });

  testWidgets('macOS Store credential reset requires explicit consent and uses macOS body', (
    tester,
  ) async {
    final attempt = Completer<void>();
    var resets = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CredentialRecoveryScreen(
          onRetry: () async {},
          onReset: () {
            resets++;
            return attempt.future;
          },
        ),
      ),
    );
    expect(find.textContaining('restore Keychain access'), findsOneWidget);
    expect(find.textContaining('Windows user'), findsNothing);
    final reset = find.widgetWithText(AppButton, 'Clear credentials and continue');
    expect(tester.widget<AppButton>(reset).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump();
    expect(resets, 1);
    expect(tester.widget<AppButton>(reset).onPressed, isNull);
    attempt.completeError(StateError('private key details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private key details'), findsNothing);
    expect(tester.widget<AppButton>(reset).onPressed, isNotNull);
  });

  testWidgets('retry is serialized and errors leave recovery available', (tester) async {
    final attempt = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CredentialRecoveryScreen(
          onRetry: () {
            calls++;
            return attempt.future;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(tester.widget<AppButton>(find.byType(AppButton)).loading, isTrue);
    await tester.ensureVisible(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    expect(calls, 1);
    attempt.completeError(StateError('synthetic-private-details'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(find.byType(AppButton)).loading, isFalse);
    expect(find.textContaining('synthetic-private-details'), findsNothing);
    expect(find.byType(CredentialRecoveryScreen), findsOneWidget);
  });

  testWidgets('Windows recovery and migration screens lay out across widths and locales', (
    tester,
  ) async {
    for (final size in const [Size(390, 844), Size(1024, 768), Size(1440, 900)]) {
      for (final locale in AppLocalizations.supportedLocales) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final state = InstallationMigrationState()
          ..source = r'C:\Users\Artist\AppData\Roaming\Joycai\Joycai Image AI Toolkits'
          ..acknowledged = true;

        for (final recovery in [true, false]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: appLocalizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildAppTheme(
                accent: AppConstants.presetThemes.values.first,
                brightness: Brightness.light,
                fontFamily: 'NotoSansSC',
              ),
              home: recovery
                  ? CredentialRecoveryScreen(
                      isWindows: true,
                      onRetry: () async {},
                      onReset: () async {},
                    )
                  : InstallationMigrationScreen(state: state, onContinue: () {}, windows: true),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size $locale recovery=$recovery');
        }

        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      }
    }
  });
}
