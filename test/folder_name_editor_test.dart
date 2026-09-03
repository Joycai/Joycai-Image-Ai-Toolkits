import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/folder_name_editor.dart';

/// The in-row name field's contract: Enter commits a good name, Enter on a
/// bad one shows why and commits nothing, Escape and an unchanged name both
/// cancel, and a commit the disk refuses keeps the field open with the reason.
void main() {
  late List<String> submitted;
  late int cancelled;
  String? nextFailure;

  setUp(() {
    submitted = [];
    cancelled = 0;
    nextFailure = null;
  });

  Future<void> pump(WidgetTester tester, {String initial = 'cha'}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: FolderNameEditor(
            initialName: initial,
            validate: (name) => name.trim() == 'taken' ? 'A folder with this name already exists' : null,
            onSubmit: (name) async {
              submitted.add(name);
              return nextFailure;
            },
            onCancel: () => cancelled++,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('opens with the whole name selected and focused', (tester) async {
    await pump(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.selection.start, 0);
    expect(field.controller!.selection.end, 3);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Enter commits a valid name', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'sketch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, ['sketch']);
    expect(cancelled, 0);
  });

  testWidgets('Enter on an invalid name shows the reason and commits nothing', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'taken');
    await tester.pump();
    expect(find.text('A folder with this name already exists'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, isEmpty);
    expect(cancelled, 0);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Escape cancels', (tester) async {
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(cancelled, 1);
    expect(submitted, isEmpty);
  });

  testWidgets('an unchanged name is a cancel, not a commit', (tester) async {
    await pump(tester);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, isEmpty);
    expect(cancelled, 1);
  });

  testWidgets('a refused commit keeps the field open with the message', (tester) async {
    nextFailure = 'Operation failed: access denied';
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'sketch');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, ['sketch']);
    expect(find.text('Operation failed: access denied'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(cancelled, 0);
  });
}
