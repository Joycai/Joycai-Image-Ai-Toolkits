// Screenshots of the task queue, the prompts screen and settings: the screen
// matrix, an opened queue row, the phone menu, an empty filter, the floating
// task capsule, and the settings pages a level deeper. See
// docs/ui-screenshot-harness.md.
//
//   flutter test test/screenshots
//   flutter test test/screenshots/app_screens_tasks_settings_test.dart

@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/task_list_ordering.dart';
import 'package:joycai_image_ai_toolkits/services/task_queue_service.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/task_capsule_monitor.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  shootMatrix(() => env, const <AppScreen>[
    AppScreen.tasks,
    AppScreen.prompts,
    AppScreen.settings,
  ]);

  // The phone-width settings shot only ever photographs the category list;
  // the appearance card — where the theme-colour chooser takes its compact
  // dot form (`D1a 20e`) — is a page deeper and was invisible to the suite.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('settings · appearance @ mobile ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.settings,
        size: kShotSizes.first,
        brightness: brightness,
        suffix: 'appearance',
        after: (WidgetTester tester) async {
          await tester.tap(find.text('外观').first);
          await settle(tester);
        },
      );
    });
  }

  // The About category is a page of its own (`E1 · 2a`) and the default
  // settings shot never opens it. The phone form stacks the identity block
  // (`2b`), which is the only part of the page that changes shape.
  for (final (ShotSize size, Brightness brightness) in <(ShotSize, Brightness)>[
    (kShotSizes.last, Brightness.light),
    (kShotSizes.last, Brightness.dark),
    (kShotSizes.first, Brightness.light),
  ]) {
    testWidgets('settings · about @ ${size.label} ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.settings,
        size: size,
        brightness: brightness,
        suffix: 'about',
        after: (WidgetTester tester) async {
          await tester.tap(find.text('关于').first);
          await settle(tester);
          // The runtime block's data directory is real disk I/O, which the
          // fake-async zone a widget test runs in never advances — without
          // this the block photographs four blank values.
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await settle(tester);
        },
      );
    });
  }

  // A queue row opened. `C1 10i` is most of what a row can show — the log, the
  // parameters, the outputs, the way out — and all of it is behind a tap, so
  // the matrix only ever photographs the collapsed third of this screen.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('tasks · expanded @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.tasks,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'expanded',
        // Console collapsed: the panel is the point of this shot, and an
        // expanded console leaves it a third of the window to open into.
        before: (_) async => AppState().isConsoleExpanded = false,
        after: (WidgetTester tester) async {
          // The failed row: the one whose detail panel has something to say.
          // Found by its model, the one only the failed fixture task uses.
          await tester.tap(find.text('gemini-2.5-flash').first);
          for (int p = 0; p < 5; p++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
      );
    });
  }

  // The phone's more-menu (`C1 11c`): sort, pin and the bulk actions, all
  // behind one button, and a hand-positioned `showMenu` — the one thing on
  // this screen a wrong anchor would put off the edge of a 375px window.
  testWidgets('tasks · menu @ mobile light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.tasks,
      size: kShotSizes.first,
      brightness: Brightness.light,
      suffix: 'menu',
      after: (WidgetTester tester) async {
        await tester.tap(find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert),
        ));
        for (int p = 0; p < 5; p++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
    );
  });

  // A filter with nothing in it (`C1 11d`): the counts stay, the block is a
  // size down from the queue's own empty state, and the one button puts the
  // filter back. The fixture has every status, so the failed rows are lifted
  // out of the live queue for the shot and put back after it.
  testWidgets('tasks · filteredEmpty @ desktop light', (WidgetTester tester) async {
    final List<TaskItem> queue = AppState().taskQueue.queue;
    final List<TaskItem> lifted = queue
        .where((TaskItem t) => t.status == TaskStatus.failed || t.status == TaskStatus.cancelled)
        .toList();
    try {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.tasks,
        size: kShotSizes.last,
        brightness: Brightness.light,
        suffix: 'filteredEmpty',
        before: (_) async {
          queue.removeWhere(lifted.contains);
          AppState().taskListState.setFilter(TaskFilter.failed);
        },
      );
    } finally {
      queue.addAll(lifted);
      AppState().taskListState.setFilter(TaskFilter.all);
      AppState().taskQueue.refreshQueue();
    }
  });

  // The floating task capsule, opened. It is only on screen while the queue has
  // work and no screen is already showing that queue, and its interesting half
  // — the per-task rows — is behind a tap, so no matrix shot has ever caught
  // it. Photographed on the prompts screen for the first reason: `C1` keeps it
  // off both the workbench and the queue.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('prompts · capsule @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.prompts,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'capsule',
        after: (WidgetTester tester) async {
          await tester.tap(find.byType(TaskCapsuleMonitor));
          for (int p = 0; p < 5; p++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        },
      );
    });
  }
}
