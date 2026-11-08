import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/batch/task_queue_screen.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_list_ordering.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import '../../screenshots/harness/fixture_env.dart';
import '../../screenshots/harness/shoot.dart';
import '../../screenshots/harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((value) => env = value);

  Future<void> open(WidgetTester tester, double width, Locale locale) => mountApp(
    tester,
    env: env,
    screen: AppScreen.tasks,
    size: Size(width, 900),
    locale: locale,
    label: 'task-controls',
    before: (_) async {
      AppState().taskListState.setFilter(TaskFilter.all);
      await AppState().taskListState.setPinActive(true);
    },
  );

  void action(WidgetTester tester, Finder finder, SemanticsAction action) {
    tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      tester.getSemantics(finder).id,
      action,
    );
  }

  for (final locale in [
    const Locale('en'),
    const Locale('zh'),
    const Locale('zh', 'Hant'),
    const Locale('ja'),
  ]) {
    for (final width in [390.0, 1440.0]) {
      testWidgets('status filters expose names, counts and keyboard selection $locale $width', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          await open(tester, width, locale);
          final l10n = AppLocalizations.of(tester.element(find.byType(TaskQueueScreen)))!;
          final state = AppState().taskListState;
          final entries = [
            (TaskFilter.all, l10n.filterAll),
            (TaskFilter.running, l10n.processingTasks),
            (TaskFilter.pending, l10n.pendingTasks),
            (TaskFilter.done, l10n.completedTasks),
            (TaskFilter.failed, l10n.failedTasks),
          ];
          var changes = 0;
          void changed() => changes++;
          state.addListener(changed);
          addTearDown(() => state.removeListener(changed));

          // Accessible activation selects an item; activating it again is inert.
          final all = find.bySemanticsLabel(l10n.filterAll);
          action(tester, all, SemanticsAction.focus);
          await settle(tester);
          for (var i = 0; i < entries.length; i++) {
            final (filter, label) = entries[i];
            final option = find.bySemanticsLabel(label);
            expect(option, findsOneWidget);
            final node = tester.getSemantics(option);
            expect(node.flagsCollection.isFocused, Tristate.isTrue);
            expect(
              node.getSemanticsData().value,
              '${AppState().taskQueue.queue.where(filter.matches).length}',
            );
            expect(node.flagsCollection.isButton, isTrue);
            expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await settle(tester);
            expect(state.filter, filter);
            expect(tester.getSemantics(option).flagsCollection.isSelected, Tristate.isTrue);
            final before = changes;
            action(tester, option, SemanticsAction.tap);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await settle(tester);
            expect(changes, before);
            expect(tester.getSemantics(option).flagsCollection.isFocused, Tristate.isTrue);
            final rect = tester.getRect(option);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            if (i < entries.length - 1) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await settle(tester);
            }
          }
          // Reverse traversal still includes the selected last option.
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await settle(tester);
          expect(
            tester
                .getSemantics(find.bySemanticsLabel(l10n.completedTasks))
                .flagsCollection
                .isFocused,
            Tristate.isTrue,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  for (final width in [834.0, 1440.0]) {
    testWidgets('pin switch has one named focus stop and toggles once at $width', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await open(tester, width, const Locale('zh'));
        final l10n = AppLocalizations.of(tester.element(find.byType(TaskQueueScreen)))!;
        final pin = find.bySemanticsLabel(l10n.pinActiveTasks);
        expect(pin, findsOneWidget);
        final node = tester.getSemantics(pin);
        expect(node.flagsCollection.isToggled, Tristate.isTrue);
        action(tester, pin, SemanticsAction.focus);
        await settle(tester);
        expect(tester.getSemantics(pin).flagsCollection.isFocused, Tristate.isTrue);
        await actInRealAsync(tester, () async {
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
        });
        expect(AppState().taskListState.pinActive, isFalse);
        expect(tester.getSemantics(pin).flagsCollection.isToggled, Tristate.isFalse);
        await actInRealAsync(tester, () async => action(tester, pin, SemanticsAction.tap));
        expect(AppState().taskListState.pinActive, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await settle(tester);
        expect(tester.getSemantics(pin).flagsCollection.isFocused, isNot(Tristate.isTrue));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await settle(tester);
        expect(tester.getSemantics(pin).flagsCollection.isFocused, Tristate.isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
