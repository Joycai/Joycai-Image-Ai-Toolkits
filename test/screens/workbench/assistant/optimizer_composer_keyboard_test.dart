import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/assistant/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';

void main() {
  Future<({TextEditingController input, List<int> sends})> pump(
    WidgetTester tester,
    AssistantMode mode, {
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ui = WorkbenchUIState()..optimizerSession = PromptOptimizerSession(mode: mode);
    final input = TextEditingController();
    final sends = <int>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkbenchUIState>.value(
        value: ui,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PromptOptimizerChatView(
              inputCtrl: input,
              onSend: () => sends.add(1),
              onRetry: () {},
              onApplyPrompt: (_) {},
              onApplyKbEdit: (_) {},
              onRejectKbEdit: (_) {},
              onAnswerAskUser: (_, _) {},
              isBusy: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (input: input, sends: sends);
  }

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter]) {
    testWidgets('${key.keyLabel} confirms IME text before sending', (tester) async {
      final host = await pump(tester, AssistantMode.systemPrompt);
      await tester.showKeyboard(find.byType(TextField));
      const composing = TextEditingValue(
        text: 'draw nihao',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 5, end: 10),
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();

      // The native IME must receive this key: neither send nor Flutter's
      // default newline shortcut may consume it.
      final handled = await tester.sendKeyDownEvent(key);
      expect(handled, isFalse);
      expect(host.sends, isEmpty);
      expect(host.input.value, composing);

      // The IME commits the raw Latin text before releasing Enter.
      tester.testTextInput.updateEditingValue(composing.copyWith(composing: TextRange.empty));
      await tester.sendKeyUpEvent(key);
      expect(host.sends, isEmpty);
      await tester.sendKeyEvent(key);
      expect(host.sends, hasLength(1));
      expect(host.input.text, 'draw nihao');
    });
  }

  testWidgets('Shift+Enter leaves newline input to the text field', (tester) async {
    final host = await pump(tester, AssistantMode.systemPrompt);
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(handled, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(host.sends, isEmpty);
    // Hardware key simulation does not synthesize the platform text update.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'draft\n', selection: TextSelection.collapsed(offset: 6)),
    );
    expect(host.input.text, 'draft\n');
    expect(host.sends, isEmpty);
  });
}
