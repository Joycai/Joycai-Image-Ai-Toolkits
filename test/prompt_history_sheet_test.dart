import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/prompt_history_entry.dart';
import 'package:joycai_image_ai_toolkits/widgets/dialogs/prompt_history_dialog.dart';

/// Drives the recent-prompt picker the way a user does: open, tap an entry,
/// read the preview, confirm. Applying replaces whatever is in the editor, so
/// the confirmation step is the point of the feature — these pin it down.
void main() {
  PromptHistoryEntry entry(String content, {int minutesAgo = 5}) => PromptHistoryEntry(
        id: content.hashCode,
        type: PromptHistoryType.image,
        content: content,
        usedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      );

  /// Pumps the sheet inline (not via `show`) so the test drives the sheet's own
  /// widget tree rather than a route.
  Future<List<String>> pumpSheet(WidgetTester tester, List<PromptHistoryEntry> entries) async {
    final applied = <String>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PromptHistorySheet(
          entries: entries,
          onApply: applied.add,
          onClear: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return applied;
  }

  testWidgets('tapping an entry previews it without applying', (tester) async {
    final applied = await pumpSheet(tester, [entry('a watercolour cat')]);

    await tester.tap(find.text('a watercolour cat'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    // Nothing is replaced until the user confirms.
    expect(applied, isEmpty);
  });

  testWidgets('confirming the preview applies the prompt', (tester) async {
    final applied = await pumpSheet(tester, [entry('a watercolour cat')]);

    await tester.tap(find.text('a watercolour cat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use This Prompt'));
    await tester.pumpAndSettle();

    expect(applied, ['a watercolour cat']);
  });

  testWidgets('cancelling the preview leaves the prompt untouched', (tester) async {
    final applied = await pumpSheet(tester, [entry('a watercolour cat')]);

    await tester.tap(find.text('a watercolour cat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(applied, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('preview shows the whole prompt, not the truncated card text', (tester) async {
    // Cards clamp to 3 lines; the preview is where the user reads the rest.
    final long = List.generate(40, (i) => 'line $i').join('\n');
    await pumpSheet(tester, [entry(long)]);

    await tester.tap(find.textContaining('line 0'));
    await tester.pumpAndSettle();

    final preview = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(preview.data, long);
  });

  testWidgets('entries are listed with a relative timestamp', (tester) async {
    await pumpSheet(tester, [
      entry('newest', minutesAgo: 0),
      entry('older', minutesAgo: 30),
    ]);

    expect(find.text('Just now'), findsOneWidget);
    expect(find.text('30 min ago'), findsOneWidget);
  });

  testWidgets('empty history shows an explanation instead of a blank panel', (tester) async {
    await pumpSheet(tester, []);

    expect(find.text('No recent prompts'), findsOneWidget);
    expect(find.text('Prompts you submit will appear here.'), findsOneWidget);
  });

  testWidgets('clear asks before wiping and only fires on confirm', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PromptHistorySheet(
          entries: [entry('a watercolour cat')],
          onApply: (_) {},
          onClear: () => cleared++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cleared, 0);

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });
}
