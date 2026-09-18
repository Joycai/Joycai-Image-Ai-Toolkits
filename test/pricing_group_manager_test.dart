import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/design_tokens.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_row.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/pricing_group_manager.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/spec_rate_table.dart';
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
      // Bracketed: the row shows 「MJ」 as a badge beside the name.
      await state.addPricingGroup({
        'name': 'Midjourney Relax [MJ]',
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
  ///
  /// [fill] hosts the manager the way the usage page does on a desktop: given
  /// the whole height, no page scroll, its list scrolling in its own column.
  Future<void> pumpManager(
    WidgetTester tester,
    AppState appState,
    Size size, {
    bool fill = false,
    int? initialEditGroupId,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final manager = PricingGroupManager(fill: fill, initialEditGroupId: initialEditGroupId);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: fill ? manager : SingleChildScrollView(child: manager),
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

  testWidgets('a bracketed part of the name is shown as a badge', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    // The name proper and the tag, with the brackets gone.
    expect(find.text('Midjourney Relax'), findsOneWidget);
    expect(find.text('MJ'), findsOneWidget);
    expect(find.text('Midjourney Relax [MJ]'), findsNothing);
  });

  testWidgets('edit and delete sit at the row\'s right edge, whatever the tags need', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    // The request-billed group has one tag, the token-billed one three; the
    // buttons end at the row's inner edge on both rather than trailing the
    // tags wherever they stop.
    for (final name in ['Midjourney Relax', 'Gemini 2.5 Pro']) {
      final row = find.ancestor(of: find.textContaining(name), matching: find.byType(FeeGroupRow)).first;
      final delete = find.descendant(of: row, matching: find.byTooltip('Delete'));
      expect(
        tester.getRect(row).right - tester.getRect(delete).right,
        closeTo(AppSpace.s6, 0.5),
        reason: name,
      );
    }
    // The badge does not take half the name column: the name is whole.
    final painter = tester.renderObject<RenderParagraph>(find.text('Midjourney Relax'));
    expect(painter.didExceedMaxLines, isFalse);
  });

  testWidgets('a group reports the models it prices', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    expect(find.text('2 models'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: find.text('2 models'), matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, 'claude-sonnet-5\nclaude-opus-4-6');
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

  testWidgets('saving closes the editor and the row shows the new name', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));
    await openEditor(tester, find.text('Veo 3 Video'));

    await tester.enterText(find.widgetWithText(TextField, 'Veo 3 Video'), 'Veo 3.1 Video');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    });
    // The save is a real database write. Wait for its effect rather than a
    // fixed slice of wall time: 300 ms was enough locally and not on a busy
    // CI runner, where the editor was still open when the assertion ran.
    for (var i = 0; i < 50 && find.text('Edit group').evaluate().isNotEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Edit group'), findsNothing);
    expect(find.text('Pick a group to edit'), findsOneWidget);
    expect(find.text('Veo 3.1 Video'), findsOneWidget);
  });

  testWidgets('opens the editor with the cache field blank when unset', (tester) async {
    final appState = await seedState(tester, cachePrice: null);
    await pumpManager(tester, appState, const Size(1920, 1080));
    await openEditor(tester, find.textContaining('Gemini 2.5 Pro'));

    // Blank (not "0") is what makes the field mean "follow the input price";
    // pre-filling a zero here would quietly turn the cache free on next save.
    final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Cache'));
    expect(field.controller?.text, isEmpty);
    expect(find.textContaining('a blank cache rate follows the input rate'), findsOneWidget);
    // The blank field hints the rate it would inherit from the input field.
    expect(field.decoration?.hintText, '1.25');
  });

  testWidgets('the add button opens the same editor the rows do', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));
    await openEditor(tester, find.widgetWithText(FilledButton, 'New Group'));

    // Once as the header's button (now tint-selected), once as the card's title.
    expect(find.text('New Group'), findsNWidgets(2));
    // The redesigned shell, not the old AlertDialog: both billing modes on show
    // at once, short accent-labelled price fields, and a blank name to fill in.
    expect(find.text('Per token'), findsOneWidget);
    expect(find.text('Per request'), findsOneWidget);
    expect(find.text('Per spec'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Input'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    final name = tester.widget<TextField>(find.widgetWithText(TextField, 'Name this group'));
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
      expect(find.text('Edit group'), findsOneWidget);
      expect(find.text('Group Name'), findsOneWidget);

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
    // One dollar sign: the l10n string carries it, the code must not add its own.
    expect(find.text('Price \$/s'), findsOneWidget);
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

  testWidgets('the editor opens in the right column and the list does not move', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    // `D2 · 1d`: the right column holds a placeholder until a group is picked.
    expect(find.text('Pick a group to edit'), findsOneWidget);
    final before = tester.getRect(find.text('Midjourney Relax'));

    await openEditor(tester, find.text('Veo 3 Video'));

    expect(find.text('Pick a group to edit'), findsNothing);
    expect(find.text('Edit group'), findsOneWidget);
    expect(find.text('Delete group'), findsOneWidget);
    // The two columns keep their places whatever the right one shows, and the
    // editor is beside the list, not under it.
    expect(tester.getRect(find.text('Midjourney Relax')), before);
    expect(
      tester.getRect(find.text('Edit group')).left,
      greaterThan(tester.getRect(find.text('Veo 3 Video').first).right),
    );
  });

  testWidgets('a new group cannot be saved until it has a name', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));
    await openEditor(tester, find.widgetWithText(FilledButton, 'New Group'));

    // `1f`: no delete for a group that does not exist yet; Save waits for a name.
    expect(find.text('Delete group'), findsNothing);
    FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save().onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Name this group'), 'Flash tier');
    await tester.pump();

    expect(save().onPressed, isNotNull);
  });

  testWidgets('on a tablet the editor opens under the tapped row', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(820, 1180));
    final relaxBefore = tester.getRect(find.text('Midjourney Relax'));

    await openEditor(tester, find.textContaining('Gemini 2.5 Pro'));

    // `1h`: no placeholder column below desktop — the card is inlined between
    // the edited row and the next, which moves down for it.
    expect(find.text('Pick a group to edit'), findsNothing);
    final title = tester.getRect(find.text('Edit group'));
    expect(title.top, greaterThan(tester.getRect(find.textContaining('Gemini 2.5 Pro').first).bottom));
    expect(title.bottom, lessThan(tester.getRect(find.text('Midjourney Relax')).top));
    expect(tester.getRect(find.text('Midjourney Relax')).top, greaterThan(relaxBefore.top));
  });

  testWidgets('filtering narrows the list and turns reordering off', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    await tester.enterText(find.widgetWithText(TextField, 'Filter fee groups…'), 'veo');
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Midjourney Relax'), findsNothing);
    expect(find.text('Veo 3 Video'), findsOneWidget);
    // `1g`: a filtered list cannot be reordered, and says so.
    expect(find.text('Reordering is off while filtering; the order saves on release.'), findsOneWidget);
    final sort = tester.widget<IconButton>(
      find.ancestor(of: find.byTooltip('Reorder'), matching: find.byType(IconButton)),
    );
    expect(sort.onPressed, isNull);
  });

  testWidgets('reorder mode shows every grip, and a move is stored', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(1920, 1080));

    await tester.tap(find.byTooltip('Reorder'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // `1g`: grips on every row without hovering, and the placeholder explains.
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
    expect(find.text('Drag the handles to reorder'), findsOneWidget);

    // The drag itself is the framework's; what is ours is that the move lands
    // in storage and comes back in that order.
    await tester.runAsync(() => appState.reorderPricingGroups(2, 0));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(appState.allPricingGroups.first.name, 'Veo 3 Video');
    expect(tester.getRect(find.text('Veo 3 Video')).top, lessThan(tester.getRect(find.text('Midjourney Relax')).top));

    await tester.runAsync(() => appState.refreshDataCache());
    final names = appState.allPricingGroups.map((g) => g.name).toList();
    expect(names.first, 'Veo 3 Video');
    expect(names.last, 'Midjourney Relax [MJ]');
  });

  /// Enough groups to run past a 1080 window, so the list has to scroll.
  Future<int> seedManyGroups(WidgetTester tester, AppState appState) async {
    final ids = await tester.runAsync(() async {
      final ids = <int>[];
      for (var i = 0; i < 30; i++) {
        ids.add(await appState.addPricingGroup({
          'name': 'Extra Group $i',
          'billing_mode': 'request',
          'request_price': 0.01 * (i + 1),
        }));
      }
      return ids;
    });
    return ids!.last;
  }

  testWidgets('on a desktop the list scrolls in its column and the editor stays in view', (tester) async {
    final appState = await seedState(tester);
    await seedManyGroups(tester, appState);
    await pumpManager(tester, appState, const Size(1920, 1080), fill: true);

    final heading = tester.getRect(find.text('New Group'));
    final placeholder = tester.getRect(find.text('Pick a group to edit'));
    expect(tester.getRect(find.text('Extra Group 29')).top, greaterThan(1080), reason: 'the last group starts below the fold');

    // Scroll the list column — the outer scrollable, not the reorder list's
    // own inert one — until the last row is on screen, and open it.
    final column = find.descendant(of: find.byType(SingleChildScrollView).first, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Extra Group 29'), 400, scrollable: column);
    await tester.pump();
    await openEditor(tester, find.text('Extra Group 29'));

    // The heading has not moved, the editor sits where the placeholder was
    // — at the top of its column, in view — and the list stays scrolled.
    expect(tester.getRect(find.text('New Group')), heading);
    expect(tester.getRect(find.text('Edit group')).top, lessThan(placeholder.top + 40));
    expect(find.text('Extra Group 29'), findsWidgets);
    expect(tester.getRect(find.text('Extra Group 29').first).bottom, lessThanOrEqualTo(1080));
  });

  testWidgets('a group opened from elsewhere is scrolled into view', (tester) async {
    final appState = await seedState(tester);
    final lastId = await seedManyGroups(tester, appState);
    await pumpManager(tester, appState, const Size(1920, 1080), fill: true, initialEditGroupId: lastId);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Edit group'), findsOneWidget);
    final row = tester.getRect(find.text('Extra Group 29').first);
    expect(row.top, greaterThan(0));
    expect(row.bottom, lessThanOrEqualTo(1080));
  });

  testWidgets('on a phone a card opens the full-screen editor', (tester) async {
    final appState = await seedState(tester);
    await pumpManager(tester, appState, const Size(390, 844));

    // `1h`: two-line cards, no header of their own.
    expect(find.text('Pick a group to edit'), findsNothing);
    expect(find.text('New Group'), findsNothing);

    await openEditor(tester, find.text('Veo 3 Video'));

    expect(tester.takeException(), isNull);
    expect(find.text('Edit group'), findsOneWidget);
    expect(find.text('Other specs'), findsOneWidget);
    expect(find.text('Models using it'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

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
