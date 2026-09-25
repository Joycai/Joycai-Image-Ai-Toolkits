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
        // Real async from the button on: a choice in this menu is persisted,
        // and it is the *opening* tap that owns the future the choice comes
        // back through — so that is the tap that decides which clock the
        // write runs on.
        await actInRealAsync(tester, () => tester.tap(sortButton()));
        final Finder group = find.text('按渠道分组');
        if (group.evaluate().isEmpty) return;
        await actInRealAsync(tester, () => tester.tap(group, warnIfMissed: false));
        await actInRealAsync(
          tester,
          () => tester.tap(
            sortButton().evaluate().isEmpty ? find.byIcon(Icons.arrow_upward) : sortButton(),
          ),
        );
        final Finder kind = find.text('类型').last;
        if (kind.evaluate().isEmpty) return;
        await actInRealAsync(tester, () => tester.tap(kind, warnIfMissed: false));
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
          // No resting button means 'ungrouped' above already left the list
          // sorted by 类型, which is the picture. Run on its own this picks
          // the key itself, and that is a write: real async from the opening
          // tap, as there.
          if (sortButton().evaluate().isEmpty) return;
          await actInRealAsync(tester, () => tester.tap(sortButton()));
          final Finder kind = find.text('类型').last;
          if (kind.evaluate().isEmpty) return;
          await actInRealAsync(tester, () => tester.tap(kind, warnIfMissed: false));
        },
      );
    });
  }
}
