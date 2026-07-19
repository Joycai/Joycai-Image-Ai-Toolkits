import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';

/// Pins the ask_user question card: a pending card gates its confirm button on
/// every question being answered, submits the choices it collected, and a
/// resolved card offers no actions at all.
void main() {
  /// A session whose transcript holds one pending two-question card, built
  /// through the restore path so no test-only staging hook is needed.
  PromptOptimizerSession sessionWithPendingCard() {
    final live = PromptOptimizerSession(mode: AssistantMode.systemPrompt);
    live.addUserTurn('优化提示词');
    live.history.add(LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [
        LLMToolCall(
          id: 'ask_1',
          name: 'ask_user',
          arguments: {
            'questions': [
              {
                'header': '鞋型',
                'question': '鞋子是哪种类型？',
                'options': [
                  {'label': '一体袜靴'},
                  {'label': '普通短靴'},
                ],
              },
              {
                'header': '画幅',
                'question': '想用哪种画幅？',
                'multi_select': true,
                'options': [
                  {'label': '3:2'},
                  {'label': '9:16'},
                ],
              },
            ],
          },
        ),
      ],
    ));
    return PromptOptimizerSession.fromStored(
      id: 'ui_test',
      mode: AssistantMode.systemPrompt,
      history: [for (final m in live.history) LLMMessage.fromJson(m.toJson())],
    );
  }

  Future<void> pumpChat(
    WidgetTester tester,
    PromptOptimizerSession session, {
    void Function(String, List<AskUserAnswer>)? onAnswer,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ui = WorkbenchUIState();
    ui.optimizerSession = session;

    await tester.pumpWidget(ChangeNotifierProvider<WorkbenchUIState>.value(
      value: ui,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PromptOptimizerChatView(
            inputCtrl: TextEditingController(),
            onSend: () {},
            onRetry: () {},
            onApplyPrompt: (_) {},
            onApplyKbEdit: (_) {},
            onRejectKbEdit: (_) {},
            onAnswerAskUser: onAnswer ?? (_, _) {},
            isBusy: false,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  FilledButton confirmButton(WidgetTester tester) => tester.widget(
        find.ancestor(
          of: find.text('Send answers'),
          matching: find.byType(FilledButton),
        ),
      );

  testWidgets('confirm stays disabled until every question is answered',
      (tester) async {
    await pumpChat(tester, sessionWithPendingCard());

    expect(find.text('鞋子是哪种类型？'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNull);

    await tester.tap(find.text('一体袜靴'));
    await tester.pumpAndSettle();
    expect(confirmButton(tester).onPressed, isNull, reason: 'question 2 unanswered');

    await tester.tap(find.text('9:16'));
    await tester.pumpAndSettle();
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('submitting delivers the selections to the callback', (tester) async {
    String? gotCallId;
    List<AskUserAnswer>? gotAnswers;
    await pumpChat(
      tester,
      sessionWithPendingCard(),
      onAnswer: (callId, answers) {
        gotCallId = callId;
        gotAnswers = answers;
      },
    );

    await tester.tap(find.text('普通短靴'));
    // Multi-select: both options.
    await tester.tap(find.text('3:2'));
    await tester.tap(find.text('9:16'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send answers'));
    await tester.pumpAndSettle();

    expect(gotCallId, 'ask_1');
    expect(gotAnswers, hasLength(2));
    expect(gotAnswers![0].selected, ['普通短靴']);
    expect(gotAnswers![1].selected, ['3:2', '9:16']);
  });

  testWidgets('an answered card renders collapsed with no actions', (tester) async {
    final session = sessionWithPendingCard();
    PromptOptimizerAgent.answerAskUser(
      session: session,
      callId: 'ask_1',
      answers: const [
        AskUserAnswer(header: '鞋型', selected: ['一体袜靴']),
        AskUserAnswer(header: '画幅', selected: ['3:2']),
      ],
    );
    await pumpChat(tester, session);

    expect(find.text('Answered'), findsOneWidget);
    expect(find.text('Send answers'), findsNothing);
    expect(find.text('鞋型: 一体袜靴'), findsOneWidget);
  });
}
