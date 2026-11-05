// Runs around every test file under test/ — except those in test/screenshots/,
// which has a config of its own (flutter_test takes the nearest one).

import 'dart:async';

import 'package:joycai_image_ai_toolkits/services/privacy/ai_consent_service.dart';

import 'support/fake_async_database_rule.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Existing protocol fixtures use local/mock transports. Consent behavior has
  // its own isolated tests; never read the user's permission database here.
  AiConsentService.instance = AiConsentService.withStore(
    read: () async => null,
    write: (_) async {},
  )..requestConsent = (_) async => true;
  installFakeAsyncDatabaseRule();
  await testMain();
}
