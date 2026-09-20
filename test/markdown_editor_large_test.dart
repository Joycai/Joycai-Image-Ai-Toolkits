import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
    ValueChanged<String>? onChanged,
    Locale? locale,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = TextEditingController(text: text);
    bool markdown = isMarkdown;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
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
                onChanged: onChanged,
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

    // One header: the small editor's Markdown row is not repeated inside.
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
    expect(inDialog(find.text('3 chars · 1 line')), findsOneWidget);

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

  testWidgets('the field survives every change of view', (tester) async {
    await open(tester, const Size(1440, 900));
    final before = tester.state(inDialog(find.byType(EditableText)));

    for (final label in ['Split', 'Preview', 'Edit']) {
      await tester.tap(inDialog(find.text(label)).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(tester.state(inDialog(find.byType(EditableText))), same(before));
  });

  testWidgets('Tab indents and tells the caller; read-only it does nothing', (tester) async {
    final changes = <String>[];
    final controller = await open(tester, const Size(1440, 900), text: 'ab', onChanged: changes.add);
    await tester.tap(inDialog(find.byType(TextField)));
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, '  ab');
    expect(changes, ['  ab']);
  });

  testWidgets('read-only: Tab leaves the text alone, and the preview follows the controller', (tester) async {
    final controller = await open(tester, const Size(1440, 900), isRefined: true, text: 'first');
    expect(inDialog(find.text('first')), findsOneWidget);
    controller.text = 'second';
    await tester.pump();
    expect(inDialog(find.text('second')), findsOneWidget);

    await tester.tap(inDialog(find.text('Source')));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.byType(TextField)));
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(controller.text, 'second');
  });

  testWidgets('resizing across the phone breakpoint switches form and keeps the editor', (tester) async {
    await open(tester, const Size(1440, 900));
    final before = tester.state(inDialog(find.byType(EditableText)));
    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(inDialog(find.byIcon(Icons.arrow_back)), findsOneWidget);
    expect(tester.state(inDialog(find.byType(EditableText))), same(before));
  });

  testWidgets('phone: copying is confirmed on the menu button', (tester) async {
    await open(tester, const Size(390, 844));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    await tester.tap(inDialog(find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy all'));
    await tester.pumpAndSettle();
    expect(inDialog(find.byIcon(Icons.check)), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(inDialog(find.byIcon(Icons.more_vert)), findsOneWidget);
  });

  testWidgets('in preview the hidden field holds no focus; back in edit it has it', (tester) async {
    await open(tester, const Size(1440, 900));
    final editable = inDialog(find.byType(EditableText));
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);

    await tester.tap(inDialog(find.text('Preview')));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(find.byType(EditableText, skipOffstage: false).last).focusNode.hasFocus, isFalse);

    await tester.tap(inDialog(find.text('Edit')));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
  });

  testWidgets('view segments are equal, 56 at the least, and never cut a label', (tester) async {
    await open(tester, const Size(1440, 900));
    final edit = tester.getRect(inDialog(find.text('Edit')));
    final split = tester.getRect(inDialog(find.text('Split')));
    final preview = tester.getRect(inDialog(find.text('Preview')));
    final pitch = split.center.dx - edit.center.dx;
    expect(pitch, greaterThanOrEqualTo(56));
    expect(preview.center.dx - split.center.dx, closeTo(pitch, 0.5));
  });

  testWidgets('a long label widens the segments instead of being cut', (tester) async {
    await open(tester, const Size(1440, 900), locale: const Locale('ja'));
    final label = inDialog(find.text('プレビュー'));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.width, greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)));
  });

  testWidgets('the word Markdown is part of the switch', (tester) async {
    await open(tester, const Size(1440, 900));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    expect(find.text('Preview'), findsNothing);
  });

  testWidgets('in the pop-out too, the word Markdown is part of the switch', (tester) async {
    await open(tester, const Size(1440, 900));
    expect(inDialog(find.text('Preview')), findsWidgets);
    await tester.tap(inDialog(find.text('Markdown')));
    await tester.pumpAndSettle();
    expect(inDialog(find.text('Preview')), findsNothing);
  });

  testWidgets('typing rebuilds the pop-out only while a preview is on screen', (tester) async {
    final controller = await open(tester, const Size(1440, 900));
    // The same widget instance after a pump means its parent did not rebuild.
    Widget header() => tester.widget(inDialog(find.byIcon(Icons.close_fullscreen)));

    Widget before = header();
    controller.text = 'a';
    await tester.pump();
    expect(identical(header(), before), isTrue);

    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    before = header();
    controller.text = 'ab';
    await tester.pump();
    expect(identical(header(), before), isFalse);

    // Too narrow for the split: what is shown is the edit view again.
    tester.view.physicalSize = const Size(800, 900);
    await tester.pumpAndSettle();
    expect(find.text('Split'), findsNothing);
    before = header();
    controller.text = 'abc';
    await tester.pump();
    expect(identical(header(), before), isTrue);
  });

  testWidgets('the pop-out open, a swapped-in controller is still coloured by the switch', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TextEditingController controller = MarkdownTextEditingController(text: '## a');
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return SizedBox(
            width: 340,
            child: MarkdownEditor(
              controller: controller,
              label: 'Prompt',
              isMarkdown: false,
              onMarkdownChanged: (_) {},
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();

    final swapped = MarkdownTextEditingController(text: '## b');
    expect(swapped.highlight, isTrue);
    rebuild(() => controller = swapped);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(swapped.highlight, isFalse);
  });

  testWidgets('closing keeps what the pop-out asked for until the caller says otherwise', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MarkdownTextEditingController(text: '## a');
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 340,
          // A caller that saves first and has not rebuilt by the time of close.
          child: MarkdownEditor(controller: controller, label: 'Prompt', isMarkdown: true, onMarkdownChanged: (_) {}),
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.byType(AppSwitch)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(controller.highlight, isFalse);
  });

  testWidgets('Markdown off stops the syntax colouring, in both editors', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MarkdownTextEditingController(text: '## Subject');
    bool markdown = true;
    await tester.pumpWidget(MaterialApp(
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
            ),
          ),
        ),
      ),
    ));
    bool coloured(Finder editable) {
      final state = tester.state<EditableTextState>(editable);
      return (state.buildTextSpan().children ?? const []).any((c) => c.style?.fontWeight == FontWeight.bold);
    }

    expect(coloured(find.byType(EditableText)), isTrue);

    // Coloured, and the IME's composing run is still underlined — across the
    // heading's own span, keeping its weight.
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    controller.value = const TextEditingValue(
      text: '## Subject',
      selection: TextSelection.collapsed(offset: 10),
      composing: TextRange(start: 3, end: 10),
    );
    await tester.pump();
    final spans = tester.state<EditableTextState>(find.byType(EditableText)).buildTextSpan().children!;
    expect(spans.map((c) => (c as TextSpan).text).join(), '## Subject');
    final run = spans.cast<TextSpan>().singleWhere((c) => c.style?.decoration == TextDecoration.underline);
    expect(run.text, 'Subject');
    expect(run.style?.fontWeight, FontWeight.bold);
    controller.value = const TextEditingValue(text: '## Subject', selection: TextSelection.collapsed(offset: 10));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    await tester.tap(inDialog(find.byType(AppSwitch)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(controller.highlight, isFalse);
    expect(coloured(inDialog(find.byType(EditableText))), isFalse);

    // Plain, but still the base class's span: the IME's composing run keeps
    // its underline.
    final field = inDialog(find.byType(EditableText));
    await tester.tap(field);
    await tester.pump();
    controller.value = const TextEditingValue(
      text: '## Subject',
      selection: TextSelection.collapsed(offset: 10),
      composing: TextRange(start: 3, end: 10),
    );
    await tester.pump();
    final composing = tester.state<EditableTextState>(field).buildTextSpan().children ?? const <InlineSpan>[];
    expect(composing.any((c) => c.style?.decoration == TextDecoration.underline), isTrue);
    controller.value = const TextEditingValue(text: '## Subject', selection: TextSelection.collapsed(offset: 10));

    // Set from outside a build, it repaints on its own.
    int notified = 0;
    controller.addListener(() => notified++);
    controller.highlight = true;
    expect(notified, 1);
    controller.highlight = false;

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(coloured(find.byType(EditableText)), isFalse);
  });
}
