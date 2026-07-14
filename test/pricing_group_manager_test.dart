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
  late Directory dbDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // A database directory of this file's own. Point path_provider at the
    // shared systemTemp and every test file opens the same database file —
    // `flutter test` runs files concurrently, so the wipe below would delete
    // rows out from under a neighbouring file mid-assertion.
    dbDir = Directory.systemTemp.createTempSync('joycai_fee_group_test');
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

  /// Seeds via [WidgetTester.runAsync]: sqflite does real I/O, which never
  /// completes inside the fake-async zone `testWidgets` runs in.
  ///
  /// AppState and DatabaseService are singletons over a real DB file, so rows
  /// outlive both the previous test and the previous run — wipe before seeding
  /// or the finders below match leftovers.
  ///
  /// The token group gets two models pointing at it and the request group none,
  /// so both halves of the row's consumer column are exercised.
  Future<AppState> seedState(WidgetTester tester, {double? cachePrice = 0.31}) async {
    final appState = await tester.runAsync(() async {
      final state = AppState();
      await state.refreshDataCache();
      for (final existing in [...state.allModels]) {
        await state.deleteModel(existing.id!);
      }
      for (final existing in [...state.allChannels]) {
        await state.deleteChannel(existing.id!);
      }
      for (final existing in [...state.allPricingGroups]) {
        await state.deletePricingGroup(existing.id!);
      }
      final tokenGroupId = await state.addPricingGroup({
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
      // Attached to a real channel: a model with a null channel is not a state
      // the app can produce.
      final channelId = await state.addChannel({
        'display_name': 'Fee Group Test Channel',
        'type': 'openai-api-rest',
        'endpoint': 'https://example.invalid/v1',
        'api_key': 'key-test',
      });
      for (final name in ['claude-sonnet-5', 'claude-opus-4-6']) {
        await state.addModel({
          'model_id': name,
          'model_name': name,
          'type': 'openai-api',
          'tag': 'chat',
          'channel_id': channelId,
          'fee_group_id': tokenGroupId,
        });
      }
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

  testWidgets('a group reports the models it prices', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    expect(find.text('2 models'), findsOneWidget);
    expect(find.text('claude-sonnet-5, claude-opus-4-6'), findsOneWidget);
  });

  testWidgets('a group no model uses says so', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    // An orphaned group prices nothing, and nothing else on this screen would
    // ever tell you — the request-billed group has no models pointing at it.
    expect(find.text('Not used by any model'), findsOneWidget);
  });

  testWidgets('an unset cache rate is shown inheriting the input rate', (tester) async {
    final appState = await seedState(tester, cachePrice: null);
    await pumpManager(tester, appState, const Size(1920, 1080));

    // Input and cache both read 1.2500 — the cache pill reports what it
    // inherits, rather than hiding the rate or implying the cache is free.
    expect(find.text('\$1.2500/M'), findsNWidgets(2));
  });

  /// Taps a group row and lets its editor come up.
  Future<void> openEditor(WidgetTester tester, Finder row) async {
    await tester.tap(row);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('opens the editor with the cache field blank when unset', (tester) async {
    final appState = await seedState(tester, cachePrice: null);
    await pumpManager(tester, appState, const Size(1920, 1080));
    await openEditor(tester, find.textContaining('Gemini 2.5 Pro'));

    // Blank (not "0") is what makes the field mean "follow the input price";
    // pre-filling a zero here would quietly turn the cache free on next save.
    final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Cache'));
    expect(field.controller?.text, isEmpty);
    expect(find.text('Leave empty to bill cache hits at the input price'), findsOneWidget);
    // The blank field hints the rate it would inherit from the input field.
    expect(field.decoration?.hintText, '1.25');
  });

  testWidgets('the add button opens the same editor the rows do', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));
    await openEditor(tester, find.widgetWithText(FilledButton, 'Add Fee Group'));

    expect(find.text('Add Fee Group'), findsWidgets);
    // The redesigned shell, not the old AlertDialog: segmented billing mode,
    // short accent-labelled price fields, and a blank name to fill in.
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Input'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    final name = tester.widget<TextField>(find.widgetWithText(TextField, 'Group Name'));
    expect(name.controller?.text, isEmpty);
  });

  for (final entry in {
    'Mobile': const Size(390, 844),
    'Tablet': const Size(820, 1180),
    'Desktop': const Size(1920, 1080),
  }.entries) {
    testWidgets('editor lays out without overflow on ${entry.key}', (tester) async {
      final appState = await seedState(tester);
      await pumpManager(tester, appState, entry.value);
      await openEditor(tester, find.textContaining('Gemini 2.5 Pro'));

      expect(tester.takeException(), isNull, reason: 'Overflow detected on ${entry.key}');
      expect(find.text('Edit Fee Group'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Group Name'), findsOneWidget);

      // Switching to per-request billing swaps the three token fields for the
      // single request one.
      await tester.tap(find.text('Per Request'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull, reason: 'Overflow after mode switch on ${entry.key}');
      expect(find.widgetWithText(TextField, 'Request'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Cache'), findsNothing);
    });
  }
}
