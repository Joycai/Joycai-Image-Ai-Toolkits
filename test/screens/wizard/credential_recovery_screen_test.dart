import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/credential_recovery_screen.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';

void main() {
  testWidgets('retry is serialized and errors leave recovery available', (tester) async {
    final attempt = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CredentialRecoveryScreen(
          onRetry: () {
            calls++;
            return attempt.future;
          },
        ),
      ),
    );
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(tester.widget<AppButton>(find.byType(AppButton)).loading, isTrue);
    await tester.tap(find.byType(AppButton));
    expect(calls, 1);
    attempt.completeError(StateError('synthetic-private-details'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(find.byType(AppButton)).loading, isFalse);
    expect(find.textContaining('synthetic-private-details'), findsNothing);
    expect(find.byType(CredentialRecoveryScreen), findsOneWidget);
  });
}
