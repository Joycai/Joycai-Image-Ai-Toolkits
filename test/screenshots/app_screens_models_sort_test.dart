// The model list's sort control (`D1d`): the filter row's button at rest, its
// menu open on the glass, and the row once the list has left its default
// order — which is the state the two faces exist for, so it is the one worth
// a picture at both widths.
//
//   flutter test test/screenshots/app_screens_models_sort_test.dart

@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  // `Icons.sort` is the resting face and appears nowhere else on this screen;
  // once a key is picked the button wears a direction arrow instead, which is
  // why the lit shot below finds it by tooltip.
  Finder sortButton() => find.byIcon(Icons.sort);

  for (final Brightness brightness in Brightness.values) {
    testWidgets('models · sortMenu @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'sortMenu',
        after: (WidgetTester tester) async {
          if (sortButton().evaluate().isEmpty) return;
          await tester.tap(sortButton());
          await settle(tester);
        },
      );
    });
  }

  // The phone (`2e`): the title-bar button's menu with its grouping row, and
  // the tab once that row is off — one run across every channel, each card
  // naming its own.
  testWidgets('models · sortMenu @ mobile light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.models,
      size: kShotSizes.firstWhere((ShotSize s) => s.label == 'mobile'),
      brightness: Brightness.light,
      suffix: 'sortMenu',
      after: (WidgetTester tester) async {
        if (sortButton().evaluate().isEmpty) return;
        await tester.tap(sortButton());
        await settle(tester);
      },
    );
  });

  testWidgets('models · ungrouped @ mobile light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.models,
      size: kShotSizes.firstWhere((ShotSize s) => s.label == 'mobile'),
      brightness: Brightness.light,
      suffix: 'ungrouped',
      after: (WidgetTester tester) async {
        if (sortButton().evaluate().isEmpty) return;
        await tester.tap(sortButton());
        await settle(tester);
        final Finder group = find.text('按渠道分组');
        if (group.evaluate().isEmpty) return;
        await tester.tap(group, warnIfMissed: false);
        await settle(tester);
        await tester.tap(sortButton().evaluate().isEmpty ? find.byIcon(Icons.arrow_upward) : sortButton());
        await settle(tester);
        final Finder kind = find.text('类型').last;
        if (kind.evaluate().isEmpty) return;
        await tester.tap(kind, warnIfMissed: false);
        await settle(tester);
      },
    );
  });

  // Lit: the accent wash, the direction arrow, and — at desktop width — the
  // key's name beside it. The tablet shot is the same state one degradation
  // step down, where the name has gone and the button has not.
  for (final String sizeLabel in const <String>['desktop', 'tablet']) {
    testWidgets('models · sorted @ $sizeLabel light', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: kShotSizes.firstWhere((ShotSize s) => s.label == sizeLabel),
        brightness: Brightness.light,
        suffix: 'sorted',
        after: (WidgetTester tester) async {
          if (sortButton().evaluate().isEmpty) return;
          await tester.tap(sortButton());
          await settle(tester);
          final Finder kind = find.text('类型').last;
          if (kind.evaluate().isEmpty) return;
          await tester.tap(kind, warnIfMissed: false);
          await settle(tester);
        },
      );
    });
  }
}
