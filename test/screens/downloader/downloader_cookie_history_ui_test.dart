import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/downloader/widgets/downloader_advanced_dialog.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/cookie_repository.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:provider/provider.dart';

import '../../screenshots/harness/fixture_env.dart';

/// The cookie history panel (S3): a retention choice above the list, a remove
/// on each row, and a clear-all — and all of it fits a phone.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  setUpAll(() async {
    env = installFixtureEnv(binding);
    await AppState().downloaderState.loadCookieHistory();
  });

  // Real time: the database answers on the real event loop.
  Future<void> seed() async {
    await CookieRepository().setRetention(CookieRetention.month);
    await CookieRepository().clear();
    await AppState().downloaderState.saveCookie('a.example', 'sid=1; x=2');
    await AppState().downloaderState.saveCookie('b.example', 'sid=3');
  }
  tearDownAll(() => env.dispose());

  // A tap starts the database work inside fake time: its continuations run
  // only as frames are pumped, and its IO only completes in real time.
  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('remove one, then switch remembering off, at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final appState = AppState();
      final state = appState.downloaderState;
      await tester.runAsync(seed);

      final prefix = TextEditingController();
      final cookies = TextEditingController();
      addTearDown(prefix.dispose);
      addTearDown(cookies.dispose);
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDownloaderAdvancedDialog(
                    context,
                    prefixController: prefix,
                    cookieController: cookies,
                    onImportCookie: () {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.cookieHistory));
      await tester.pumpAndSettle();

      expect(find.text(l10n.cookieRetentionMonth), findsOneWidget);
      expect(find.text('a.example'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The innermost row holding a.example that holds one remove button.
      final rowOfA = find.ancestor(of: find.text('a.example'), matching: find.byType(Row)).evaluate().firstWhere(
            (row) => find
                .descendant(of: find.byElementPredicate((e) => e == row), matching: find.byTooltip(l10n.cookieHistoryForget))
                .evaluate()
                .length == 1,
          );
      final removeA = find.descendant(
        of: find.byElementPredicate((e) => e == rowOfA),
        matching: find.byTooltip(l10n.cookieHistoryForget),
      );
      await tester.ensureVisible(removeA);
      await tester.pumpAndSettle();
      await tester.tap(removeA);
      await settleDb(tester);
      expect(find.text('a.example'), findsNothing);
      expect(find.text('b.example'), findsOneWidget);

      await tester.ensureVisible(find.text(l10n.cookieRetentionOff));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cookieRetentionOff));
      await settleDb(tester);
      expect(find.text('b.example'), findsNothing);
      expect(state.cookieRetention, CookieRetention.off);
      expect(tester.takeException(), isNull);

      await tester.runAsync(() => CookieRepository().setRetention(CookieRetention.month));
    });
  }
}
