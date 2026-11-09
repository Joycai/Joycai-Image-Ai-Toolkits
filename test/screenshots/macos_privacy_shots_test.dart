@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      for (final locale in [const Locale('zh'), if (size == kShotSizes.first) const Locale('ja')]) {
        for (final dialog in [false, true]) {
          testWidgets('macOS privacy ${size.label} ${brightness.name} $locale dialog=$dialog', (
            tester,
          ) async {
            await shoot(
              tester,
              env: env,
              screen: AppScreen.settings,
              size: size,
              brightness: brightness,
              locale: locale,
              suffix: '${dialog ? 'diskAccessDialog' : 'diskAccess'}_${locale.languageCode}',
              after: (tester) async {
                final l10n = lookupAppLocalizations(locale);
                await actInRealAsync(tester, () => tester.tap(find.text(l10n.application).first));
                await tester.ensureVisible(find.text(l10n.macFullDiskAccessHelp));
                if (dialog) await tester.tap(find.text(l10n.macFullDiskAccessHelp));
                await settle(tester, 6);
              },
            );
          }, skip: !Platform.isMacOS);
        }
      }
    }
  }
}
