import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/pricing_group_manager.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renders the fee-group list.
///
/// Each row lines a name up against three price pills, so these pump every
/// breakpoint the project supports to catch overflow, and pin what the pills
/// report — in particular that a group with no cache rate of its own shows the
/// input rate it inherits rather than a free one.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
  });

  /// Seeds via [WidgetTester.runAsync]: sqflite does real I/O, which never
  /// completes inside the fake-async zone `testWidgets` runs in.
  ///
  /// AppState and DatabaseService are singletons over a real DB file, so groups
  /// outlive both the previous test and the previous run — wipe before seeding
  /// or the finders below match leftovers.
  Future<AppState> seedState(WidgetTester tester, {double? cachePrice = 0.31}) async {
    final appState = await tester.runAsync(() async {
      final state = AppState();
      await state.refreshDataCache();
      for (final existing in [...state.allPricingGroups]) {
        await state.deletePricingGroup(existing.id!);
      }
      await state.addPricingGroup({
        'name': 'Gemini 2.5 Pro Long Context Tier With A Deliberately Wordy Name',
        'billing_mode': 'token',
        'input_price': 1.25,
        'cache_input_price': cachePrice,
        'output_price': 10.0,
      });
      await state.addPricingGroup({
        'name': 'Midjourney Relax',
        'billing_mode': 'request',
        'request_price': 0.04,
      });
      return state;
    });
    return appState!;
  }

  /// Pumps a bounded number of frames rather than `pumpAndSettle()`: the shared
  /// AppState keeps scheduling work in a headless test, so the tree never
  /// reaches a fully idle state and settling would spin until it times out.
  Future<void> pumpManager(WidgetTester tester, AppState appState, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: PricingGroupManager()),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final entry in {
    'Mobile': const Size(390, 844),
    'Tablet': const Size(820, 1180),
    'Desktop': const Size(1920, 1080),
  }.entries) {
    testWidgets('lays out without overflow on ${entry.key}', (tester) async {
      final appState = await seedState(tester);
      await pumpManager(tester, appState, entry.value);

      expect(tester.takeException(), isNull, reason: 'Overflow detected on ${entry.key}');
      expect(find.text('Midjourney Relax'), findsOneWidget);
    });
  }

  testWidgets('shows each token price with its own rate', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    expect(find.text('\$1.2500/M'), findsOneWidget); // input
    expect(find.text('\$0.3100/M'), findsOneWidget); // cache
    expect(find.text('\$10.0000/M'), findsOneWidget); // output
    expect(find.text('\$0.0400/Req'), findsOneWidget); // the request-billed group
  });

  testWidgets('an unset cache rate is shown inheriting the input rate', (tester) async {
    final appState = await seedState(tester, cachePrice: null);
    await pumpManager(tester, appState, const Size(1920, 1080));

    // Input and cache both read 1.2500 — the cache pill reports what it
    // inherits, rather than hiding the rate or implying the cache is free.
    expect(find.text('\$1.2500/M'), findsNWidgets(2));
  });

  testWidgets('opens the editor with the cache field blank when unset', (tester) async {
    final appState = await seedState(tester, cachePrice: null);
    await pumpManager(tester, appState, const Size(1920, 1080));

    await tester.tap(find.textContaining('Gemini 2.5 Pro'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Blank (not "0") is what makes the field mean "follow the input price";
    // pre-filling a zero here would quietly turn the cache free on next save.
    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Cached Input Price (\$/M Tokens)'),
    );
    expect(field.controller?.text, isEmpty);
    expect(find.text('Leave empty to bill cache hits at the input price'), findsOneWidget);
  });
}
