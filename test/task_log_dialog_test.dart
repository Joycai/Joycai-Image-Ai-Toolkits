import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/widgets/dialogs/task_log_dialog.dart';

/// The log viewer is the only way to see why a task failed, so these pin down
/// that it shows the whole log — not just the tail the card already showed —
/// for finished tasks as well as failed ones.
void main() {
  TaskItem task(TaskStatus status, List<String> messages) {
    final t = TaskItem(
      id: 'abcdef1234567890',
      imagePaths: ['snow.png'],
      modelId: 'gpt-image-2',
      parameters: {},
      status: status,
    );
    for (final m in messages) {
      t.addLog(m);
    }
    return t;
  }

  Future<void> pumpDialog(WidgetTester tester, TaskItem item) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TaskLogDialog(task: item)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows every line of a failed task, not just the last', (tester) async {
    await pumpDialog(
      tester,
      task(TaskStatus.failed, [
        'Start processing with model: gpt-image-2',
        'Error: quota exceeded',
        'Task finished.',
      ]),
    );

    expect(find.textContaining('Start processing with model'), findsOneWidget);
    expect(find.textContaining('Error: quota exceeded'), findsOneWidget);
    expect(find.textContaining('Task finished.'), findsOneWidget);
    expect(find.text('3 lines'), findsOneWidget);
  });

  testWidgets('a completed task can read its log too', (tester) async {
    await pumpDialog(tester, task(TaskStatus.completed, ['Saved result image to: /out/a.png']));

    expect(find.textContaining('Saved result image to'), findsOneWidget);
    // Nothing is tailing a finished task, so no live indicator.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a task with no log says so instead of showing a blank console', (tester) async {
    await pumpDialog(tester, task(TaskStatus.completed, []));

    expect(find.text('No log recorded for this task.'), findsOneWidget);
    expect(find.text('0 lines'), findsOneWidget);
  });

  testWidgets('the error line is called out against the ordinary ones', (tester) async {
    await pumpDialog(tester, task(TaskStatus.failed, ['Start processing', 'Error: quota exceeded']));

    final errorLine = tester.widget<Text>(find.textContaining('Error: quota exceeded'));
    final plainLine = tester.widget<Text>(find.textContaining('Start processing'));
    expect(errorLine.style!.color, isNot(plainLine.style!.color));
    expect(errorLine.style!.fontWeight, FontWeight.w600);
  });
}
