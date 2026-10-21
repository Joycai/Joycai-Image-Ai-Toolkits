@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((e) => env = e);
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      testWidgets('GPT timeout ${size.label} ${brightness.name}', (tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.settings,
          size: size,
          brightness: brightness,
          locale: const Locale('en'),
          suffix: 'gptTimeout',
          after: (tester) async {
            await actInRealAsync(
              tester,
              () => tester.tap(
                find.text(lookupAppLocalizations(const Locale('en')).application).first,
              ),
            );
          },
        );
      });
    }
  }
  for (final locale in [
    const Locale('ja'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('GPT timeout mobile long copy $locale', (tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.settings,
        size: kShotSizes.first,
        locale: locale,
        suffix: 'gptTimeout_${locale.toLanguageTag()}',
        after: (tester) async {
          await actInRealAsync(
            tester,
            () => tester.tap(find.text(lookupAppLocalizations(locale).application).first),
          );
        },
      );
    });
  }
}
