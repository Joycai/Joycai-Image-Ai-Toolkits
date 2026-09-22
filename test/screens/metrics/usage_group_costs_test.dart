import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_group_costs.dart';
import 'package:joycai_image_ai_toolkits/screens/metrics/widgets/usage_stats.dart';

/// Renders the per-group cost cards.
///
/// Each card's bar is a claim about proportion, so these pin what it is a
/// proportion of, and that the cards are ordered by the number they exist to
/// compare.
void main() {
  final groups = [
    PricingGroup(id: 1, name: 'Cheap Group'),
    PricingGroup(id: 2, name: 'Expensive Group'),
    PricingGroup(id: 3, name: 'Deleted Group'),
  ];

  UsageStats stats(Map<int, double> costs, {double? total, Map<int, GroupUsage> usage = const {}}) => UsageStats(
        totalInput: 1000,
        totalCache: 0,
        totalOutput: 500,
        totalRequestCount: 4,
        totalCost: total ?? costs.values.fold(0.0, (a, b) => a + b),
        groupCosts: costs,
        groupUsage: usage,
      );

  /// A spec-billed group's usage: 126 seconds over 18 requests, 3 of which
  /// no rate row priced.
  const veoUsage = GroupUsage(
    specCost: 6.2,
    specUnits: {OutputUnit.second: 126},
    unmatchedCount: 3,
    requestCount: 18,
  );

  Future<void> pumpCosts(
    WidgetTester tester,
    UsageStats data,
    Size size, {
    List<PricingGroup>? known,
    ValueChanged<PricingGroup>? onFixRates,
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
            child: UsageGroupCosts(stats: data, groups: known ?? groups, onFixRates: onFixRates),
          ),
        ),
      ),
    );
    // The share bars grow in; read them where they settle.
    await tester.pumpAndSettle();
  }

  for (final entry in {
    'Mobile': const Size(390, 844),
    'Tablet': const Size(820, 1180),
    'Desktop': const Size(1920, 1080),
  }.entries) {
    testWidgets('lays out without overflow on ${entry.key}', (tester) async {
      await pumpCosts(tester, stats({1: 0.5, 2: 1.5}), entry.value);

      expect(tester.takeException(), isNull, reason: 'Overflow on ${entry.key}');
      expect(find.text('Usage by Group'), findsOneWidget);
      expect(find.text('\$1.5000'), findsOneWidget);
    });
  }

  testWidgets('bars measure each group against the range total', (tester) async {
    // Not against the largest group: scaled to the biggest, the top group fills
    // the track every time and the bar stops saying anything.
    await pumpCosts(tester, stats({1: 0.5, 2: 1.5}), const Size(1920, 1080));

    final bars = tester
        .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .toList();
    expect(bars.length, 2);
    expect(bars[0].value, closeTo(0.75, 1e-9)); // 1.5 of 2.0
    expect(bars[1].value, closeTo(0.25, 1e-9)); // 0.5 of 2.0
  });

  testWidgets('a bar grows from nothing the first time it is shown', (tester) async {
    await pumpCosts(tester, stats({1: 0.5, 2: 1.5}), const Size(1920, 1080));
    // Mounted afresh: the first frame starts at zero.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: UsageGroupCosts(stats: stats({1: 0.5, 2: 1.5}), groups: groups)),
    ));
    double first() => tester
        .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .first
        .value!;
    expect(first(), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(first(), inExclusiveRange(0, 0.75));
    await tester.pumpAndSettle();
    expect(first(), closeTo(0.75, 1e-9));
  });

  testWidgets('orders groups by what they cost', (tester) async {
    await pumpCosts(tester, stats({1: 0.5, 2: 1.5}), const Size(1920, 1080));

    // One card of rows now: the dearer group is the row above.
    expect(
      tester.getRect(find.text('Expensive Group')).top,
      lessThan(tester.getRect(find.text('Cheap Group')).top),
    );
  });

  testWidgets('a group deleted since its usage was recorded is left out', (tester) async {
    // Its cost still counts toward the total — the money was spent — but there
    // is no name left to put on a card.
    await pumpCosts(
      tester,
      stats({1: 0.5, 3: 1.5}),
      const Size(1920, 1080),
      known: [groups[0]],
    );

    expect(find.text('Cheap Group'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('nothing to attribute renders nothing', (tester) async {
    await pumpCosts(tester, stats({}), const Size(1920, 1080));

    expect(find.text('Usage by Group'), findsNothing);
  });

  testWidgets('a zero-cost range does not divide by it', (tester) async {
    await pumpCosts(tester, stats({1: 0.0}, total: 0.0), const Size(1920, 1080));

    expect(tester.takeException(), isNull);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 0);
  });

  testWidgets('a spec-billed group states its units beside its requests', (tester) async {
    await pumpCosts(tester, stats({1: 6.2, 2: 0.5}, usage: {1: veoUsage}), const Size(1920, 1080));

    expect(find.text('126 s · 18 req'), findsOneWidget);
  });

  testWidgets('the input fee is a line of the bar\'s tooltip, and only when there is one', (tester) async {
    const seedream = GroupUsage(
      specCost: 3.0,
      specInputCost: 0.34,
      specUnits: {OutputUnit.image: 10},
      requestCount: 10,
    );
    await pumpCosts(tester, stats({1: 3.34}, usage: {1: seedream}), const Size(1920, 1080));

    final messages = tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message ?? '');
    expect(messages.where((m) => m.contains('Input images: \$0.3400')), hasLength(1));
    // The quantity line does not grow: the images sent are a detail of a row.
    expect(find.text('10 images · 10 req'), findsOneWidget);

    await pumpCosts(
      tester,
      stats({1: 3.0}, usage: {1: const GroupUsage(specCost: 3.0, specUnits: {OutputUnit.image: 10}, requestCount: 10)}),
      const Size(1920, 1080),
    );
    final quiet = tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message ?? '');
    expect(quiet.where((m) => m.contains('Input images')), isEmpty);
  });

  testWidgets('what the provider priced itself is a line of the tooltip, in the neutral share (D2d)', (tester) async {
    const xai = GroupUsage(
      specCost: 0.06,
      reportedCost: 0.09,
      specUnits: {OutputUnit.image: 2},
      requestCount: 2,
    );
    await pumpCosts(tester, stats({1: 0.15}, usage: {1: xai}), const Size(1920, 1080));

    final messages = tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message ?? '');
    expect(messages.where((m) => m.contains('Reported cost: \$0.0900')), hasLength(1));
    // Both are money that bought output: the bar has one neutral segment,
    // sized by their sum — nothing of the reported part is left unpainted.
    expect(xai.totalCost, closeTo(0.15, 1e-9));
    expect(find.text('2 images · 2 req'), findsOneWidget);
  });

  testWidgets('unpriced requests are counted under the group, with a way to fix them', (tester) async {
    PricingGroup? asked;
    await pumpCosts(
      tester,
      stats({1: 6.2, 2: 0.5}, usage: {1: veoUsage}),
      const Size(1920, 1080),
      onFixRates: (g) => asked = g,
    );

    expect(find.text('3 requests matched no rate and were billed at 0'), findsOneWidget);
    await tester.tap(find.text('Add rates'));
    await tester.pump();
    expect(asked?.id, 1);
  });

  testWidgets('a matched group carries no note and no button', (tester) async {
    await pumpCosts(
      tester,
      stats({1: 6.2}, usage: {1: const GroupUsage(specCost: 6.2, specUnits: {OutputUnit.image: 38}, requestCount: 31)}),
      const Size(1920, 1080),
      onFixRates: (_) {},
    );

    expect(find.text('38 images · 31 req'), findsOneWidget);
    expect(find.textContaining('matched no rate'), findsNothing);
    expect(find.text('Add rates'), findsNothing);
  });

  for (final entry in {
    'Mobile': const Size(390, 844),
    'Tablet': const Size(820, 1180),
  }.entries) {
    testWidgets('the unmatched note lays out without overflow on ${entry.key}', (tester) async {
      await pumpCosts(
        tester,
        stats({1: 6.2, 2: 0.5}, usage: {1: veoUsage}),
        entry.value,
        onFixRates: (_) {},
      );

      expect(tester.takeException(), isNull, reason: 'Overflow on ${entry.key}');
      expect(find.text('126 s · 18 req'), findsOneWidget);
      expect(find.text('Add rates'), findsOneWidget);
    });
  }
}
