import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/settings/widgets/content_safety_section.dart';

void main() {
  for (final result in [true, false, PlatformException(code: 'no_mail_handler')]) {
    testWidgets('report keeps copy fallback after mail result $result', (tester) async {
      final urls = <String>[];
      String? clipboard;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      messenger.setMockMethodCallHandler(launcher, (call) async {
        expect(call.method, 'launch');
        urls.add(call.arguments['url'] as String);
        if (result is Exception) throw result;
        return result;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = call.arguments['text'] as String;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: ContentSafetySection())),
        ),
      );
      await tester.tap(find.text(l10n.contentSafetyEmail));
      await tester.pumpAndSettle();
      expect(urls, ['mailto:${ContentSafetySection.email}']);
      expect(
        find.text(l10n.contentSafetyEmailFailed),
        result == true ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.text(l10n.contentSafetyCopyEmail));
      await tester.pumpAndSettle();
      expect(clipboard, ContentSafetySection.email);
      expect(urls, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}
