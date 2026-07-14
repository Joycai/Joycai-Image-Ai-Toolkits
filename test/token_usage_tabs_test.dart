import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/token_usage_screen.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the usage / fee-groups view tabs.
///
/// They navigate between two pages while sharing a header with a range filter
/// that only filters the current one, so what these pin is that the tabs stay
/// distinct from that filter and actually swap the body.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dbDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // A database directory of this file's own. Point path_provider at the
    // shared systemTemp and every test file opens the same database file —
    // `flutter test` runs files concurrently, so they race for its lock and
    // whichever one does the most I/O loses with "database is locked".
    dbDir = Directory.systemTemp.createTempSync('joycai_usage_tabs_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => dbDir.path,
    );
  });

  tearDownAll(() {
    try {
      dbDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The database handle may still be open; the OS reaps temp dirs anyway.
    }
  });

  /// Mounts the screen inside [WidgetTester.runAsync].
  ///
  /// Both usage views query the database from `initState`, and sqflite does
  /// real I/O on a real timer — mounted in the fake-async zone that
  /// `testWidgets` runs in, that timer is still pending when the tree is torn
  /// down and the test fails on the way out. Pumping frames afterwards (rather
  /// than `pumpAndSettle()`) keeps the shared AppState from spinning forever.
  Future<void> pumpScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final state = AppState();
      await state.refreshDataCache();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TokenUsageScreen(),
          ),
        ),
      );
      // Let the initState query land while timers are still real.
      await Future.delayed(const Duration(milliseconds: 400));
    });

    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final entry in {
    'Tablet': const Size(820, 1180),
    'Desktop': const Size(1920, 1080),
  }.entries) {
    testWidgets('tabs swap the view without overflow on ${entry.key}', (tester) async {
      await pumpScreen(tester, entry.value);

      expect(tester.takeException(), isNull, reason: 'Overflow on ${entry.key}');
      expect(find.text('Usage'), findsOneWidget);
      expect(find.text('Fee Groups'), findsOneWidget);

      await tester.tap(find.text('Fee Groups'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull, reason: 'Overflow after switch on ${entry.key}');
      // The fee-groups body replaced the usage body, and the tabs survived the
      // swap so there is a way back.
      expect(find.text('Add Fee Group'), findsWidgets);
      expect(find.text('Usage'), findsOneWidget);
    });
  }

  for (final entry in {
    'Tablet': const Size(820, 1180),
    'Desktop': const Size(1920, 1080),
  }.entries) {
    testWidgets('the tabs stay put when the view changes on ${entry.key}', (tester) async {
      await pumpScreen(tester, entry.value);

      final usageBefore = tester.getRect(find.text('Usage'));
      final feeGroupsBefore = tester.getRect(find.text('Fee Groups'));

      await tester.tap(find.text('Fee Groups'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // The usage view stacks summary cards above its card and the fee-group
      // view does not. With the tabs inside a card header, that difference slid
      // them down the screen on every switch — navigation must not move under
      // the pointer that is aiming at it.
      expect(tester.getRect(find.text('Usage')), usageBefore);
      expect(tester.getRect(find.text('Fee Groups')), feeGroupsBefore);
    });
  }

  testWidgets('the view tabs are not shaped like the range filter', (tester) async {
    await pumpScreen(tester, const Size(1920, 1080));

    // The header holds exactly one SegmentedButton — the range presets. The
    // view tabs used to be a second one sitting right beside it, which is what
    // made navigation read as another filter.
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.text('Last Week'), findsOneWidget);

    // The old title echoed the nav rail's own label from the header's most
    // valuable slot; the tabs have it now.
    expect(find.text('Token Usage Metrics'), findsNothing);
  });
}
