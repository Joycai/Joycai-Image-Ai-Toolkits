import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/main.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize FFI for desktop (windows/linux/macos) unit tests
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    // Set a large surface size to mimic desktop
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const MyApp(version: '1.1.0'),
      ),
    );

    // Wait for the async initialization in AppState (loadSettings)
    // We pump a few frames to allow async ops to start, though strictly 
    // async filesystem/db calls might not complete without proper mocking.
    // For a smoke test, we just want to ensure the UI renders without crashing.
    await tester.pump();

    // Verify that the NavigationRail is present (part of MainNavigationScreen)
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}