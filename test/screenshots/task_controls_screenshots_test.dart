@Tags(<String>['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/batch/task_queue_screen.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_list_ordering.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);

  for (final size in kShotSizes) {
    for (final brightness in Brightness.values) {
      for (final selected in [true, false]) {
        testWidgets('task filter focus ${size.label} $brightness selected=$selected', (
          tester,
        ) async {
          await shoot(
            tester,
            env: env,
            screen: AppScreen.tasks,
            size: size,
            brightness: brightness,
            suffix: selected ? 'filterSelectedFocus' : 'filterFocus',
            before: (_) async => AppState().taskListState.setFilter(TaskFilter.all),
            after: (_) async {
              final l10n = AppLocalizations.of(tester.element(find.byType(TaskQueueScreen)))!;
              final label = selected ? l10n.filterAll : l10n.failedTasks;
              // Reach the InkWell's own focus, retaining its native highlight.
              final labelFinder = find.text(label).first;
              Focus.of(tester.element(find.text(l10n.filterAll).first)).requestFocus();
              await settle(tester);
              if (selected) {
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await settle(tester);
                await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
                await settle(tester);
              } else {
                for (var i = 0; i < 4; i++) {
                  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                  await settle(tester);
                }
              }
              expect(Focus.of(tester.element(labelFinder)).hasPrimaryFocus, isTrue);
            },
          );
        });
      }
    }
  }
}
