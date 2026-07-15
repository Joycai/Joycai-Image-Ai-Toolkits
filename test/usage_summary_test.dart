import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_stats.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_summary.dart';

/// Renders the usage summary block.
///
/// It carries five numbers and a meter in a fixed-height row, so these pump
/// every breakpoint to catch overflow, and pin what the meter reports — in
/// particular that a range with no prompt tokens reads as "not asked" rather
/// than as a cache that never hits.
void main() {
  UsageStats stats({
    int input = 443807,
    int cache = 85715,
    int output = 55319,
    int requests = 63,
    double cost = 2.3348,
  }) =>
      UsageStats(
        totalInput: input,
        totalCache: cache,
        totalOutput: output,
        totalRequestCount: requests,
        totalCost: cost,
        groupCosts: {},
      );

  Future<void> pumpSummary(
    WidgetTester tester,
    UsageStats data,
    Size size, {
    bool compact = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: UsageSummary(
              stats: data, rangeLabel: 'Last Week', compact: compact),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final entry in {
    'Mobile': (const Size(390, 844), true),
    'Tablet': (const Size(820, 1180), true),
    'Desktop': (const Size(1280, 800), false),
    'Wide desktop': (const Size(1920, 1080), false),
  }.entries) {
    final (size, compact) = entry.value;

    testWidgets('lays out without overflow on ${entry.key}', (tester) async {
      await pumpSummary(tester, stats(), size, compact: compact);

      expect(tester.takeException(), isNull, reason: 'Overflow on ${entry.key}');
      // Grouped digits, not 443807 — these run to seven figures.
      expect(find.text('443,807'), findsOneWidget);
      expect(find.text('85,715'), findsOneWidget);
      expect(find.text('55,319'), findsOneWidget);
      expect(find.text('\$2.3348'), findsOneWidget);
      expect(find.text('Cache Hit Rate'), findsOneWidget);
      // The totals are totals over a period, so the period is on the card.
      expect(find.text('63 Requests'), findsOneWidget);
      expect(find.text('Last Week'), findsOneWidget);
    });
  }

  testWidgets('reports the cached share of prompt tokens', (tester) async {
    await pumpSummary(tester, stats(input: 750, cache: 250), const Size(1920, 1080));

    expect(find.text('25.0%'), findsOneWidget);
    final meter = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(meter.value, closeTo(0.25, 1e-9));
  });

  testWidgets('shows a dash, not 0%, when nothing was billed by token', (tester) async {
    // A range of only request-billed image jobs never asked the cache; "0.0%"
    // would report that as a cache that always misses.
    await pumpSummary(
      tester,
      stats(input: 0, cache: 0, output: 0, cost: 0.48),
      const Size(1920, 1080),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0.0%'), findsNothing);
    final meter = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(meter.value, 0);
  });

  testWidgets('keeps a seven-figure count from overflowing its column', (tester) async {
    // The narrowest case: compact mode splits one phone width across three
    // token counts, and a heavy month reaches eight digits.
    await pumpSummary(
      tester,
      stats(input: 12345678, cache: 87654321, output: 99999999),
      const Size(390, 844),
      compact: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('87,654,321'), findsOneWidget);
  });
}
