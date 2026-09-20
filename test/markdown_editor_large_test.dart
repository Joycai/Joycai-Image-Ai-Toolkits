import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_switch.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/markdown_editor.dart';

/// The pop-out editor (`A1d`): its own header, body and footer rather than a
/// small editor nested in a titled card.
void main() {
  Future<TextEditingController> open(
    WidgetTester tester,
    Size screen, {
    bool isMarkdown = true,
    bool isRefined = false,
    String text = '## Subject\n- one\n- two',
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = TextEditingController(text: text);
    bool markdown = isMarkdown;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 340,
              child: MarkdownEditor(
                controller: controller,
                label: 'Prompt',
                isMarkdown: markdown,
                onMarkdownChanged: (v) => setState(() => markdown = v),
                isRefined: isRefined,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return controller;
  }

  Finder inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

  testWidgets('desktop: one header, three views, a count that follows the text', (tester) async {
    final controller = await open(tester, const Size(1440, 900));

    // One header: the small editor's checkbox row is not repeated inside.
    expect(inDialog(find.byType(Checkbox)), findsNothing);
    expect(inDialog(find.byType(AppSwitch)), findsOneWidget);
    expect(inDialog(find.byIcon(Icons.close_fullscreen)), findsOneWidget);
    // Header and footer end at the same right edge — neither strands its
    // last control mid-row.
    final collapse = tester.getRect(inDialog(find.byIcon(Icons.close_fullscreen)));
    expect((tester.getRect(find.text('Done')).right - collapse.right).abs(), lessThan(24));
    expect(inDialog(find.text('Split')), findsOneWidget);
    expect(inDialog(find.text('22 chars · 3 lines')), findsOneWidget);

    controller.text = 'abc';
    await tester.pump();
    expect(inDialog(find.text('3 chars · 1 lines')), findsOneWidget);

    // Split shows the source and the rendering side by side.
    await tester.tap(inDialog(find.text('Split')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(inDialog(find.byType(TextField)), findsOneWidget);
    expect(inDialog(find.text('Source')), findsOneWidget);
  });

  testWidgets('the text is held to a measure, not run across the dialog', (tester) async {
    await open(tester, const Size(1440, 900));
    final dialog = tester.getRect(inDialog(find.byIcon(Icons.close_fullscreen)));
    final field = tester.getRect(inDialog(find.byType(TextField)));
    expect(field.width, 720);
    expect(dialog.right, greaterThan(field.right));
  });

  testWidgets('no split below the width that can hold two columns', (tester) async {
    await open(tester, const Size(800, 900));
    expect(inDialog(find.text('Split')), findsNothing);
    expect(inDialog(find.text('Preview')), findsOneWidget);
  });

  testWidgets('Markdown off removes the view toggle and leaves the rest in place', (tester) async {
    await open(tester, const Size(1440, 900));
    final before = tester.getRect(inDialog(find.byIcon(Icons.close_fullscreen)));

    await tester.tap(inDialog(find.byType(AppSwitch)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(inDialog(find.text('Preview')), findsNothing);
    expect(tester.getRect(inDialog(find.byIcon(Icons.close_fullscreen))), before);
  });

  testWidgets('the view it was left in carries back to the small editor', (tester) async {
    await open(tester, const Size(1440, 900));
    await tester.tap(inDialog(find.text('Preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('read-only: source or preview, nothing to switch, Close', (tester) async {
    await open(tester, const Size(1440, 900), isRefined: true);
    expect(inDialog(find.byType(AppSwitch)), findsNothing);
    expect(inDialog(find.text('Split')), findsNothing);
    expect(inDialog(find.text('Read-only')), findsOneWidget);
    expect(inDialog(find.text('Close')), findsOneWidget);
  });

  testWidgets('phone: fullscreen, two views, no overflow', (tester) async {
    await open(tester, const Size(390, 844));
    expect(inDialog(find.byIcon(Icons.arrow_back)), findsOneWidget);
    expect(inDialog(find.text('Split')), findsNothing);
    expect(inDialog(find.byIcon(Icons.more_vert)), findsOneWidget);

    await tester.tap(inDialog(find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    expect(find.text('Copy all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
