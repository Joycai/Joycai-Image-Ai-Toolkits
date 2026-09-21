import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/text_editing_focus.dart';

/// Pins why [isTextEditingFocused] exists: a key a text field does not
/// consume still reaches every ancestor [Focus] handler, so a screen-level
/// Delete / Backspace shortcut has to ask before acting. The first assertion
/// here is the Flutter behaviour the guard is written against — if it ever
/// stops being true, the guard is no longer load-bearing and this says so.
void main() {
  testWidgets('Backspace reaches an ancestor Focus even while a field has it', (
    WidgetTester tester,
  ) async {
    final List<LogicalKeyboardKey> seen = <LogicalKeyboardKey>[];

    await tester.pumpWidget(MaterialApp(
      home: Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) seen.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
        child: const Material(child: TextField()),
      ),
    ));

    expect(isTextEditingFocused(), isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(isTextEditingFocused(), isTrue);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(seen, contains(LogicalKeyboardKey.backspace));
  });

  testWidgets('a plain focus node is not text editing', (WidgetTester tester) async {
    final FocusNode node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Focus(focusNode: node, child: const SizedBox.expand()),
    ));
    node.requestFocus();
    await tester.pump();

    expect(isTextEditingFocused(), isFalse);
  });
}
