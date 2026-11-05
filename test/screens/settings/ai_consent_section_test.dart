import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/ai_consent_section.dart';
import 'package:joycai_image_ai_toolkits/services/privacy/ai_consent_service.dart';

void main() {
  late AiConsentService original;
  late AiConsentService service;
  final scope = AiConsentScope.forRequest(
    endpoint: 'https://example.test/v1',
    destination: Uri.parse('https://example.test/chat'),
  );
  setUp(() async {
    original = AiConsentService.instance;
    service = AiConsentService.withStore(read: () async => null, write: (_) async {})
      ..requestConsent = (_) async => true;
    AiConsentService.instance = service;
    await service.require(scope);
  });
  tearDown(() {
    AiConsentService.instance = original;
    service.dispose();
  });
  testWidgets('revoke blocks; ask next time removes decision without granting', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: AiConsentSection())),
      ),
    );
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    expect(service.isAllowed(scope), false);
    expect(find.text('Blocked'), findsOneWidget);
    await tester.tap(find.text('Ask next time'));
    await tester.pumpAndSettle();
    expect(service.isAllowed(scope), false);
    expect(service.decisions, isEmpty);
    expect(find.text('Allowed'), findsNothing);
  });
}
