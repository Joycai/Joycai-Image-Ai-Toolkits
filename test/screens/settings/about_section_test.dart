import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_distribution.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/about_section.dart';
import 'package:joycai_image_ai_toolkits/services/privacy/ai_consent_service.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late AiConsentService original;
  late AiConsentService service;

  setUp(() {
    original = AiConsentService.instance;
    service = AiConsentService.withStore(read: () async => null, write: (_) async {});
    AiConsentService.instance = service;
  });

  tearDown(() {
    AiConsentService.instance = original;
    service.dispose();
  });

  testWidgets(
    'changelog link is gated to direct distribution while privacy policy remains visible',
    (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: AboutSection())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.aboutPrivacyPolicy), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
      expect(
        find.text(l10n.aboutChangelog),
        AppDistribution.direct ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
