import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/pricing_group_manager.dart';
import 'package:joycai_image_ai_toolkits/widgets/spec_rate_table.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// Renders the fee-group grid.
///
/// Each card packs a name, the models it prices and up to three rates into one
/// column of a grid, so these pump every breakpoint the project supports to
/// catch overflow, and pin what the cards report — in particular that a group
/// with no cache rate of its own shows the input rate it inherits rather than a
/// free one.
void main() {
  // A data directory of this file's own — see the helper for why sharing one
  // is a race rather than a nuisance.
  usePrivateDataDir('joycai_fee_group_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
      // A spec-billed video group (`D2b`): per second, three rows and a
      // catch-all — the shape the summary chip and the editor's table are
      // pinned against below.
      await state.addPricingGroup({
        'name': 'Veo 3 Video',
        'billing_mode': 'spec',
        'output_unit': 'second',
        'output_rates': SpecRate.encodeList(const [
          SpecRate(size: '1080p', quality: 'high', price: 0.5),
          SpecRate(size: '1080p', price: 0.3),
          SpecRate(size: '720p', price: 0.15),
          SpecRate(price: 0.1),
        ]),
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
    // ever tell you — the request-billed and the spec-billed groups have no
    // models pointing at them.
    expect(find.text('Not used by any model'), findsNWidgets(2));
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
    // The redesigned shell, not the old AlertDialog: both billing modes on show
    // at once, short accent-labelled price fields, and a blank name to fill in.
    expect(find.text('Per token'), findsOneWidget);
    expect(find.text('Per request'), findsOneWidget);
    expect(find.text('Per spec'), findsOneWidget);
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
      await tester.tap(find.text('Per request'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull, reason: 'Overflow after mode switch on ${entry.key}');
      expect(find.widgetWithText(TextField, 'Request'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Cache'), findsNothing);
    });
  }

  testWidgets('a spec-billed group is summarised in one tag, with the table a hover away', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    // One summary however many rows: unit, priced rows, price range.
    expect(find.text('Per second · 4 rates · \$0.10–0.50'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('Per second · 4 rates · \$0.10–0.50'), matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, contains('1080p · high  \$0.5000/s'));
    expect(tooltip.message, contains('Other specs  \$0.1000/s'));
  });

  testWidgets('the spec editor opens on the rate table, and a new row blocks saving until priced', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));
    await openEditor(tester, find.text('Veo 3 Video'));

    // Three ordinary rows (two say 1080p), the pinned catch-all, the rule.
    expect(find.text('1080p'), findsNWidgets(2));
    expect(find.text('720p'), findsOneWidget);
    expect(find.text('Other specs'), findsOneWidget);
    expect(find.widgetWithText(TextField, '0.1000'), findsOneWidget);
    expect(find.textContaining('Blank means "any"'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);

    await tester.tap(find.text('Add rate'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The new row is all 「Any」 with an empty price, and the table says which
    // row is unpriced rather than outlining the field red.
    expect(find.text('Row 4 has no price yet. Add one before saving.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
  });

  for (final entry in {
    'Mobile': const Size(390, 844),
    'Tablet': const Size(820, 1180),
    'Desktop': const Size(1920, 1080),
  }.entries) {
    testWidgets('the spec editor lays out without overflow on ${entry.key}', (tester) async {
      final appState = await seedState(tester);
      await pumpManager(tester, appState, entry.value);
      await openEditor(tester, find.text('Veo 3 Video'));

      expect(tester.takeException(), isNull, reason: 'Overflow detected on ${entry.key}');
      expect(find.text('Other specs'), findsOneWidget);
    });
  }

  group('SpecTableIssues', () {
    test('names the first unpriced row, 1-based', () {
      final rows = [SpecRateDraft(size: '1K', price: '0.03'), SpecRateDraft(size: '2K'), SpecRateDraft(size: '4K')];
      expect(SpecTableIssues.of(rows).missingPriceRow, 2);
      expect(SpecTableIssues.of(rows).blocksSave, isTrue);
    });

    test('names the first pair of rows with the same conditions', () {
      final rows = [
        SpecRateDraft(size: '1080p', quality: 'high', price: '0.5'),
        SpecRateDraft(size: '720p', price: '0.15'),
        SpecRateDraft(size: '1080p', quality: 'high', price: '0.45'),
      ];
      expect(SpecTableIssues.of(rows).duplicate, (a: 1, b: 3));
    });

    test('a clean table blocks nothing, and an empty one is clean', () {
      expect(SpecTableIssues.of([SpecRateDraft(size: '1K', price: '0.03')]).blocksSave, isFalse);
      expect(SpecTableIssues.of([]).blocksSave, isFalse);
    });
  });
}
