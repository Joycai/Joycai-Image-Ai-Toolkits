import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';

/// The knowledge-optimization loop's chat surface (`20b` / `20d`): the
/// feedback entry card, the distill request entry, the composer's distill
/// chip states, and the wrap-up card's appearance rules.
void main() {
  Future<AppLocalizations> l10nEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  /// A knowledge session restored from a canned history — the same path a
  /// real restart uses, so `promptVersions`/`refinedPrompt` derive exactly as
  /// they would in production.
  PromptOptimizerSession sessionFromHistory(List<LLMMessage> history) =>
      PromptOptimizerSession.fromStored(
        id: 'test',
        mode: AssistantMode.knowledgeBase,
        history: history,
      );

  List<LLMMessage> submitTurn(String prompt, {String? note}) => [
        LLMMessage(role: LLMRole.assistant, content: '', toolCalls: [
          LLMToolCall(
            id: 'c1',
            name: 'submit_prompt',
            arguments: {'prompt': prompt, 'note': ?note},
          ),
        ]),
        LLMMessage(
          role: LLMRole.tool,
          content: '{"status":"ok"}',
          toolCallId: 'c1',
          toolName: 'submit_prompt',
        ),
      ];

  Future<void> pumpChat(
    WidgetTester tester,
    PromptOptimizerSession session, {
    bool isBusy = false,
    VoidCallback? onDistill,
    VoidCallback? onSaveFinalPrompt,
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
            onAnswerAskUser: (_, _) {},
            onDistill: onDistill,
            onSaveFinalPrompt: onSaveFinalPrompt,
            isBusy: isBusy,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('feedback entry card (20b)', () {
    testWidgets('renders the label, version chip and critique', (tester) async {
      final session = sessionFromHistory([
        LLMMessage(role: LLMRole.user, content: '优化'),
        ...submitTurn('a prompt'),
      ]);
      session.addResultFeedback(
        imageName: 'gen_1.png',
        promptVersion: 1,
        feedback: '裙摆褶皱少了一层',
      );

      await pumpChat(tester, session);
      final l10n = await l10nEn();

      expect(find.text(l10n.optResultFeedbackChatLabel), findsOneWidget);
      expect(find.text('v1'), findsWidgets);
      expect(find.text('裙摆褶皱少了一层'), findsOneWidget);
      expect(find.text('gen_1.png'), findsOneWidget);
    });
  });

  group('distill request entry', () {
    testWidgets('renders as a compact user-side card', (tester) async {
      final session = sessionFromHistory([
        LLMMessage(role: LLMRole.user, content: '优化'),
        ...submitTurn('a prompt'),
        LLMMessage(
          role: LLMRole.user,
          content: '${PromptOptimizerAgent.kbDistillMarker} go',
        ),
      ]);

      await pumpChat(tester, session);
      final l10n = await l10nEn();

      expect(find.text(l10n.optDistillAction), findsWidgets);
      expect(find.text(l10n.optKbDistillRequested), findsOneWidget);
      // The raw marker instruction must never show as a user bubble.
      expect(find.textContaining(PromptOptimizerAgent.kbDistillMarker), findsNothing);
    });
  });

  group('composer distill chip (20d a/b)', () {
    testWidgets('hidden outside knowledge sessions', (tester) async {
      final session = PromptOptimizerSession(mode: AssistantMode.systemPrompt);
      session.addUserTurn('hi');
      await pumpChat(tester, session, onDistill: () {});
      final l10n = await l10nEn();
      expect(find.text(l10n.optDistillAction), findsNothing);
    });

    testWidgets('disabled with no versions, enabled and tappable after one',
        (tester) async {
      final empty = PromptOptimizerSession(mode: AssistantMode.knowledgeBase);
      empty.addUserTurn('hi');
      var fired = 0;
      await pumpChat(tester, empty, onDistill: () => fired++);
      final l10n = await l10nEn();

      expect(find.text(l10n.optDistillAction), findsOneWidget);
      await tester.tap(find.text(l10n.optDistillAction));
      await tester.pump();
      expect(fired, 0, reason: 'no prompt versions yet — the chip must be inert');

      final ready = sessionFromHistory([
        LLMMessage(role: LLMRole.user, content: '优化'),
        ...submitTurn('a prompt'),
      ]);
      await pumpChat(tester, ready, onDistill: () => fired++);
      await tester.tap(find.text(l10n.optDistillAction));
      await tester.pump();
      expect(fired, 1);
    });
  });

  group('wrap-up card (20d d)', () {
    PromptOptimizerSession distilledSession() {
      final session = sessionFromHistory([
        LLMMessage(role: LLMRole.user, content: '优化'),
        ...submitTurn('final prompt text'),
        LLMMessage(
          role: LLMRole.user,
          content: '${PromptOptimizerAgent.kbDistillMarker} go',
        ),
      ]);
      return session;
    }

    testWidgets('appears once every staged edit is decided, with line counts',
        (tester) async {
      final session = distilledSession();
      final id = session.stageKbEditForTest(
        relPath: 'lessons.md',
        newContent: 'a\nb\nc\n',
        oldContent: 'a\n',
        note: 'added the skirt rule',
      );
      session.resolveKbEditForTest(id, KbEditState.applied);

      var saved = 0;
      await pumpChat(tester, session, onSaveFinalPrompt: () => saved++);
      final l10n = await l10nEn();

      expect(find.text(l10n.optDistillDoneTitle), findsOneWidget);
      // Twice is right: the staged-edit card's header carries the same count
      // as the wrap-up row — they describe the same approved diff.
      expect(find.text('+2'), findsAtLeastNWidgets(1));
      expect(find.text('added the skirt rule'), findsAtLeastNWidgets(1));

      await tester.ensureVisible(find.text(l10n.optSaveFinalPrompt));
      await tester.tap(find.text(l10n.optSaveFinalPrompt));
      expect(saved, 1);
    });

    testWidgets('stays hidden while an edit is still pending', (tester) async {
      final session = distilledSession();
      session.stageKbEditForTest(
        relPath: 'lessons.md',
        newContent: 'a\nb\n',
        oldContent: 'a\n',
      );

      await pumpChat(tester, session);
      final l10n = await l10nEn();
      expect(find.text(l10n.optDistillDoneTitle), findsNothing);
    });

    testWidgets('stays hidden when every edit was rejected', (tester) async {
      final session = distilledSession();
      final id = session.stageKbEditForTest(
        relPath: 'lessons.md',
        newContent: 'a\nb\n',
        oldContent: 'a\n',
      );
      session.resolveKbEditForTest(id, KbEditState.rejected);

      await pumpChat(tester, session);
      final l10n = await l10nEn();
      expect(find.text(l10n.optDistillDoneTitle), findsNothing);
    });
  });
}
