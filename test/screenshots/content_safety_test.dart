@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/content_safety_section.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((e) => env = e);
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      for (final variant in ['locked', 'warning', 'report']) {
        testWidgets('content safety ${size.label} ${brightness.name} $variant', (tester) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.settings,
            size: size,
            brightness: brightness,
            suffix: 'safety_$variant',
            after: (tester) async {
              await actInRealAsync(
                tester,
                () => tester.tap(find.text(variant == 'report' ? '关于' : '应用设置').first),
              );
              if (variant == 'warning') {
                await tester.tap(find.text('解锁调整'));
                await settle(tester);
              } else if (variant == 'report') {
                await tester.ensureVisible(find.byType(ContentSafetySection));
                await settle(tester);
              }
            },
          );
        });
      }
    }
  }
  for (final locale in [
    const Locale('en'),
    const Locale('ja'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('safety warning ${locale.toLanguageTag()}', (tester) async {
      final l10n = lookupAppLocalizations(locale);
      await shoot(
        tester,
        env: env,
        screen: AppScreen.settings,
        size: kShotSizes.first,
        locale: locale,
        suffix: 'safety_warning_${locale.toLanguageTag()}',
        after: (tester) async {
          // Application settings is the fourth category, identified by its localized label.
          await actInRealAsync(tester, () => tester.tap(find.text(l10n.application).first));
          await tester.tap(find.text(l10n.safetyUnlockTitle));
          await settle(tester);
        },
      );
    });
  }
}
