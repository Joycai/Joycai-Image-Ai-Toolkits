import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/services/privacy/ai_consent_service.dart';
import 'package:joycai_image_ai_toolkits/widgets/privacy/ai_consent_dialog.dart';

void main() {
  final scope = AiConsentScope.forRequest(
    endpoint: 'https://my-ai.example.test/v1',
    destination: Uri.parse('https://uploads.example.test/files?token=hidden'),
  );
  for (final allow in [false, true]) {
    testWidgets('only explicit allow grants sharing: $allow', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            accent: AppConstants.presetThemes.values.first,
            brightness: Brightness.light,
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await AiConsentDialog.show(context, scope);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('https://uploads.example.test'), findsOneWidget);
      expect(find.textContaining('hidden'), findsNothing);
      expect(result, isNull);
      await tester.tap(find.text(allow ? 'Allow sharing' : 'Decline'));
      await tester.pumpAndSettle();
      expect(result, allow);
    });
  }
  testWidgets('dismissing consent does not grant permission', (tester) async {
    bool? result = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await AiConsentDialog.show(context, scope);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AiConsentDialog), findsNothing);
    expect(result, isNull);
  });
}
