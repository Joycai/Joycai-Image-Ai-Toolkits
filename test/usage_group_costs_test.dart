import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/pricing_group.dart';
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

  UsageStats stats(Map<int, double> costs, {double? total}) => UsageStats(
        totalInput: 1000,
        totalCache: 0,
        totalOutput: 500,
        totalRequestCount: 4,
        totalCost: total ?? costs.values.fold(0.0, (a, b) => a + b),
        groupCosts: costs,
      );

  Future<void> pumpCosts(
    WidgetTester tester,
    UsageStats data,
    Size size, {
    List<PricingGroup>? known,
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
            child: UsageGroupCosts(stats: data, groups: known ?? groups),
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

  testWidgets('orders groups by what they cost', (tester) async {
    await pumpCosts(tester, stats({1: 0.5, 2: 1.5}), const Size(1920, 1080));

    expect(
      tester.getRect(find.text('Expensive Group')).left,
      lessThan(tester.getRect(find.text('Cheap Group')).left),
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
}
