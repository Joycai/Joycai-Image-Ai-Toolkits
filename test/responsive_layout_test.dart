import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/main.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/nav_lens_group.dart';
import 'package:joycai_image_ai_toolkits/widgets/shell/phone_dock.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

void main() {
  // A data directory of this file's own. The mock used to answer '.', which
  // is both the repository root and the same answer every other file gives —
  // `flutter test` runs files concurrently, so they raced for one database's
  // lock.
  usePrivateDataDir('joycai_responsive_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> testScreenAtSize(WidgetTester tester, Size size, String description) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;

    final appState = AppState();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: appState.taskQueue),
          ChangeNotifierProvider.value(value: appState.workbenchUIState),
          ChangeNotifierProvider.value(value: appState.fileBrowserState),
          ChangeNotifierProvider.value(value: appState.galleryState),
          ChangeNotifierProvider.value(value: appState.downloaderState),
          ChangeNotifierProvider.value(value: appState.logState),
        ],
        child: const MyApp(version: 'test'),
      ),
    );

    // Pump a bounded number of frames instead of pumpAndSettle(): the app loads
    // settings and scans directories asynchronously, so the tree never reaches
    // a fully idle state in a headless test.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Check for layout errors (e.g. RenderFlex overflows).
    expect(tester.takeException(), isNull, reason: 'Overflow or error detected at $description');
  }

  // `01 全局壳层`: below 600 the destinations live in the floating phone dock;
  // at and above it they live in the title bar (desktop) or the tablet top bar
  // (touch OS), as a lens group. There is no Material navigation widget.
  group('Responsive Layout Tests', () {
    testWidgets('Verify Mobile Layout (390x844)', (tester) async {
      await testScreenAtSize(tester, const Size(390, 844), 'Mobile');
      expect(find.byType(PhoneDock), findsOneWidget);
      expect(find.byType(NavLensGroup), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('Verify Tablet Layout (820x1180)', (tester) async {
      await testScreenAtSize(tester, const Size(820, 1180), 'Tablet');
      expect(find.byType(PhoneDock), findsNothing);
      expect(find.byType(NavLensGroup), findsOneWidget);
    });

    testWidgets('Verify Desktop Layout (1920x1080)', (tester) async {
      await testScreenAtSize(tester, const Size(1920, 1080), 'Desktop');
      expect(find.byType(PhoneDock), findsNothing);
      expect(find.byType(NavLensGroup), findsOneWidget);
    });
  });
}
