import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/browser_filter_bar.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/files/thumbnail_fit_toggle.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// The browser's filter row keeps the thumbnail-size controls against its
/// right edge however wide the window is. The categories used to sit in a
/// Flexible beside a Spacer, which split the spare room between them and left
/// the slider and fit toggle stranded short of the edge on a wide window.
void main() {
  usePrivateDataDir('joycai_filter_bar_layout_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('the size slider and fit toggle hug the right edge on a wide window', (tester) async {
    for (final double width in const [1200, 2000]) {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Constructed on the real clock: both load persisted settings.
      final states = await tester.runAsync(() async {
        final app = AppState();
        await app.refreshDataCache();
        return (app, FileBrowserState());
      });
      final (appState, browser) = states!;
      browser.viewMode = BrowserViewMode.grid;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
            ChangeNotifierProvider<FileBrowserState>.value(value: browser),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: BrowserFilterBar(state: browser),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Rect bar = tester.getRect(find.byType(BrowserFilterBar));
      final Rect toggle = tester.getRect(find.byType(ThumbnailFitToggle));
      // Only the bar's own 16px side padding past the toggle.
      expect(bar.right - toggle.right, closeTo(16, 0.5), reason: 'at $width px');
      // And the sort button stays beside the categories, not beside the slider.
      final Rect lastChip = tester.getRect(find.text('其他'));
      final Rect sort = tester.getRect(find.text('修改时间'));
      expect(sort.left - lastChip.right, lessThan(80), reason: 'at $width px');
    }
  });
}
