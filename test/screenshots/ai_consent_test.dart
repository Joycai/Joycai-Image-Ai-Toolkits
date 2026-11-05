@Tags(['screenshots'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/ai_consent_section.dart';
import 'package:joycai_image_ai_toolkits/services/privacy/ai_consent_service.dart';
import 'package:joycai_image_ai_toolkits/widgets/privacy/ai_consent_dialog.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((e) => env = e);
  final scope = AiConsentScope.forRequest(
    vendor: 'custom',
    endpoint: 'https://my-ai.example.com/v1',
    destination: Uri.parse('https://uploads.example.com/files'),
    proxy: 'http://localhost:8080',
  );
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      testWidgets('AI consent ${size.label} ${brightness.name}', (tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.settings,
          size: size,
          brightness: brightness,
          suffix: 'ai_consent',
          after: (tester) async {
            final context = tester.element(find.byType(Scaffold).first);
            unawaited(AiConsentDialog.show(context, scope));
            await settle(tester);
          },
        );
      });
    }
  }
  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      testWidgets('AI consent management ${size.label} ${brightness.name}', (tester) async {
        await shoot(
          tester,
          env: env,
          screen: AppScreen.settings,
          size: size,
          brightness: brightness,
          suffix: 'ai_consent_management',
          before: (_) async {
            await AiConsentService.instance.require(scope);
            await AiConsentService.instance.revoke(
              AiConsentScope.forRequest(
                vendor: 'custom',
                endpoint: 'https://blocked.example.com/v1',
                destination: Uri.parse('https://blocked.example.com/chat'),
              ),
            );
          },
          after: (tester) async {
            await tester.tap(find.text('关于').first);
            await settle(tester);
            await tester.ensureVisible(find.byType(AiConsentSection));
            await settle(tester);
          },
        );
      });
    }
  }
  for (final locale in [
    const Locale('en'),
    const Locale('ja'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets('AI consent mobile ${locale.toLanguageTag()}', (tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.settings,
        size: kShotSizes.first,
        locale: locale,
        suffix: 'ai_consent_${locale.toLanguageTag()}',
        after: (tester) async {
          unawaited(AiConsentDialog.show(tester.element(find.byType(Scaffold).first), scope));
          await settle(tester);
        },
      );
    });
  }
}
