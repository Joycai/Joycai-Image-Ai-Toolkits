import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/wizard/credential_recovery_screen.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_button.dart';

void main() {
  testWidgets('Windows credential reset requires explicit consent and stays serialized', (
    tester,
  ) async {
    final attempt = Completer<void>();
    var resets = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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
