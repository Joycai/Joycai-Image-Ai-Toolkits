import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/main.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/refiner_panel.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> testScreenAtSize(WidgetTester tester, Size size, String description) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;

    // Mock Path Provider
    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '.';
    });

    final appState = AppState();
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          ChangeNotifierProvider.value(value: appState.windowState),
          ChangeNotifierProvider.value(value: appState.browserState),
          ChangeNotifierProvider.value(value: appState.downloaderState),
        ],
        child: const MyApp(version: 'test'),
      ),
    );

    await tester.pumpAndSettle();

    // Check for overflows
    expect(tester.takeException(), isNull, reason: 'Overflow or error detected at $description');
  }

  group('Responsive Layout Tests', () {
    testWidgets('Verify Mobile Layout (390x844)', (tester) async {
      await testScreenAtSize(tester, const Size(390, 844), 'Mobile');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('Verify Tablet Layout (820x1180)', (tester) async {
      await testScreenAtSize(tester, const Size(820, 1180), 'Tablet');
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    testWidgets('Verify Desktop Layout (1920x1080)', (tester) async {
      await testScreenAtSize(tester, const Size(1920, 1080), 'Desktop');
      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });
}
