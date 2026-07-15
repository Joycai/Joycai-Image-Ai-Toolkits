import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_list.dart';

/// Renders the usage record table.
///
/// The table states four facts per row and one summary per day, so these pin
/// the facts it is allowed to state: a day total only where the day is whole,
/// and a cost that comes from the prices snapshotted on the row.
void main() {
  /// A token-billed row. Prices are per million, so the defaults below cost
  /// 1000 * 3.0/1e6 + 500 * 12.0/1e6 = $0.009.
  Map<String, dynamic> tokenRow({
    required String timestamp,
    String modelId = 'claude-sonnet-5',
    int input = 1000,
    int cache = 0,
    int output = 500,
  }) =>
      {
        'model_id': modelId,
        'timestamp': timestamp,
        'billing_mode': 'token',
        'input_tokens': input,
        'cache_tokens': cache,
        'output_tokens': output,
        'input_price': 3.0,
        'cache_price': 0.3,
        'output_price': 12.0,
        'request_count': 1,
      };

  Map<String, dynamic> requestRow({
    required String timestamp,
    String modelId = 'gpt-image-2',
    int count = 2,
    double price = 0.04,
  }) =>
      {
        'model_id': modelId,
        'timestamp': timestamp,
        'billing_mode': 'request',
        'request_count': count,
        'request_price': price,
      };

  /// Today's date at [hour], so "Today" is a fact about the test run rather
  /// than a date baked into it.
  String todayAt(int hour, {int minute = 0}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute).toIso8601String();
  }

  String daysAgoAt(int days, int hour) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - days, hour).toIso8601String();
  }

  Future<void> pumpList(
    WidgetTester tester,
    List<Map<String, dynamic>> rows,
    Size size, {
    bool hasMore = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: UsageList(
              usageData: rows,
              onRefresh: () {},
              hasMore: hasMore,
              isLoadingMore: false,
              onLoadMore: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final entry in {
    'Mobile': const Size(390, 844),
    'Tablet': const Size(820, 1180),
    'Desktop': const Size(1920, 1080),
  }.entries) {
    testWidgets('lays out without overflow on ${entry.key}', (tester) async {
      await pumpList(
        tester,
        [
          tokenRow(timestamp: todayAt(14, minute: 12), cache: 250),
          requestRow(timestamp: todayAt(9)),
          tokenRow(timestamp: daysAgoAt(1, 8), modelId: 'a-model-with-a-deliberately-long-name'),
        ],
        entry.value,
      );

      expect(tester.takeException(), isNull, reason: 'Overflow on ${entry.key}');
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
    });
  }

  testWidgets('groups records under the day they happened', (tester) async {
    await pumpList(
      tester,
      [
        tokenRow(timestamp: todayAt(14)),
        tokenRow(timestamp: todayAt(9)),
        requestRow(timestamp: daysAgoAt(1, 8)),
      ],
      const Size(1920, 1080),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('· 2 records'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('· 1 records'), findsOneWidget);
    // Both of today's rows cost $0.0090 each.
    expect(find.text('\$0.0180'), findsOneWidget);
  });

  testWidgets('the day totals stop at the last page loaded', (tester) async {
    // The oldest day on screen holds only the records paged in so far, so its
    // total would be wrong until the user pressed Load More — and wrong
    // quietly. Today is complete because a whole day sits below it.
    await pumpList(
      tester,
      [
        tokenRow(timestamp: todayAt(14)),
        // Twice today's row, so the two days' figures stay tellable apart.
        tokenRow(timestamp: daysAgoAt(1, 8), input: 2000, output: 1000),
      ],
      const Size(1920, 1080),
      hasMore: true,
    );

    expect(find.text('· 1 records'), findsOneWidget); // today only
    // Today's $0.0090 reads twice: its one row, and the day total. Yesterday's
    // $0.0180 reads once — the row, with no total claimed above it.
    expect(find.text('\$0.0090'), findsNWidgets(2));
    expect(find.text('\$0.0180'), findsOneWidget);
    expect(find.text('Load More'), findsOneWidget);
  });

  testWidgets('a channel prefix is lifted out of the model name', (tester) async {
    await pumpList(
      tester,
      [tokenRow(timestamp: todayAt(14), modelId: '[R]gemini-3.1-flash-image-preview')],
      const Size(1920, 1080),
    );

    // The prefix is the channel the model came through — the same handful of
    // strings down the whole column, which is what makes it a badge and not
    // part of every name.
    expect(find.text('R'), findsOneWidget);
    expect(find.text('gemini-3.1-flash-image-preview'), findsOneWidget);
  });

  testWidgets('says what was billed, by billing mode', (tester) async {
    await pumpList(
      tester,
      [
        tokenRow(timestamp: todayAt(14), input: 1500, cache: 250, output: 500),
        requestRow(timestamp: todayAt(9), count: 2),
      ],
      const Size(1920, 1080),
    );

    // Token rows count tokens, abbreviated — six digits a row defeats a column
    // meant to be compared down the page.
    expect(find.text('1.5K'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    // Request rows count requests.
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('an empty range says so', (tester) async {
    await pumpList(tester, [], const Size(1920, 1080));

    expect(find.text('No usage data in the selected range.'), findsOneWidget);
  });
}
