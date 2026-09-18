// Screenshots of channels and routes (`D1f`): a multi-route channel in the
// rail, its route table, the model editor's three route states, and the
// merge review. See docs/ui-screenshot-harness.md.
//
//   flutter test test/screenshots/app_screens_channel_routes_test.dart

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

  ShotSize sized(String label) =>
      kShotSizes.firstWhere((ShotSize s) => s.label == label);

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Settles across real I/O: the merge review reads its reference count
  /// from the database before its dialog opens.
  Future<void> settleIo(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final Finder f = find.text(text);
    if (f.evaluate().isEmpty) return;
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester);
  }

  // 4a: the relay selected — rail sublines, header, route badges on cards,
  // and the merge prompt above the search.
  for (final Brightness brightness in const <Brightness>[Brightness.light, Brightness.dark]) {
    testWidgets('routes rail @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: sized('desktop'),
        brightness: brightness,
        suffix: 'routesRail',
        after: (WidgetTester tester) => tapText(tester, 'NewAPI 中转'),
      );
    });
  }

  // 4c / 4g: the relay's route table.
  for (final (String size, Brightness brightness) in const <(String, Brightness)>[
    ('desktop', Brightness.dark),
    ('mobile', Brightness.dark),
  ]) {
    testWidgets('routes channel editor @ $size ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: sized(size),
        brightness: brightness,
        suffix: 'routesChannelEdit',
        after: (WidgetTester tester) async {
          if (size == 'mobile') {
            await tapText(tester, '渠道管理');
            await tapText(tester, 'NewAPI 中转');
          } else {
            await tapText(tester, 'NewAPI 中转');
            final Finder edit = find.byTooltip('编辑');
            if (edit.evaluate().isEmpty) return;
            await tester.tap(edit.first, warnIfMissed: false);
            await settle(tester);
          }
        },
      );
    });
  }

  // 4d: ① on Chat, ② Responses tapped (never set up: the preview), ③ after
  // switching (a blank route).
  for (final (String state, String size) in const <(String, String)>[
    ('1', 'desktop'),
    ('2', 'desktop'),
    ('3', 'desktop'),
    ('1', 'mobile'),
  ]) {
    testWidgets('routes model editor $state @ $size', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: sized(size),
        brightness: Brightness.light,
        suffix: 'routesEditor$state',
        after: (WidgetTester tester) async {
          if (size != 'mobile') await tapText(tester, '渠道管理');
          await tapText(tester, 'NewAPI 中转');
          await tapText(tester, 'GPT-5.2');
          if (state == '1') return;
          await tapText(tester, 'Responses');
          if (state == '2') return;
          await tapText(tester, '切换');
        },
      );
    });
  }

  // 4f: the merge review of the relay's two formats.
  for (final (String size, Brightness brightness) in const <(String, Brightness)>[
    ('desktop', Brightness.light),
    ('mobile', Brightness.light),
  ]) {
    testWidgets('routes merge review @ $size ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.models,
        size: sized(size),
        brightness: brightness,
        suffix: 'routesMerge',
        after: (WidgetTester tester) async {
          if (size == 'mobile') await tapText(tester, '渠道管理');
          final Finder review = find.text('查看');
          if (review.evaluate().isEmpty) return;
          await tester.tap(review.first, warnIfMissed: false);
          await settleIo(tester);
        },
      );
    });
  }
}
