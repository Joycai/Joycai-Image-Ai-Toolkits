// The three prompt-assistant frames `A2` added beside the finished one:
// `10g` (system-prompt mode), `10h` (library edit) and `10i` (running).
//
// What is pinned here is the part that is derived rather than drawn — the step
// count and the pending-edit list the header and the right panel are built
// from — plus the two layouts that have somewhere to overflow: the config
// panel at the width it narrows to, and the composer's swap of send for stop.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/optimizer_config_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_button.dart';
import 'package:provider/provider.dart';

void main() {
  Future<AppLocalizations> en() => AppLocalizations.delegate.load(const Locale('en'));

  group('the running turn reports its own steps', () {
    test('counts tool calls since the last user turn, not since the session began', () {
      // Two turns, four tool calls between them. A count over the whole
      // transcript would say "step 4" at the start of the second turn, which
      // is a claim about a turn that has done nothing yet.
      final session = PromptOptimizerSession.fromStored(
        id: 's',
        mode: AssistantMode.knowledgeBase,
        history: <LLMMessage>[
          LLMMessage(role: LLMRole.user, content: 'first'),
          LLMMessage(role: LLMRole.assistant, content: '', toolCalls: <LLMToolCall>[
            LLMToolCall(id: 'a', name: 'view_image', arguments: <String, dynamic>{'id': '1'}),
            LLMToolCall(id: 'b', name: 'view_image', arguments: <String, dynamic>{'id': '2'}),
          ]),
          for (final id in <String>['a', 'b'])
            LLMMessage(role: LLMRole.tool, content: 'ok', toolCallId: id, toolName: 'view_image'),
          LLMMessage(role: LLMRole.assistant, content: 'done'),
          LLMMessage(role: LLMRole.user, content: 'second'),
          LLMMessage(role: LLMRole.assistant, content: '', toolCalls: <LLMToolCall>[
            LLMToolCall(
              id: 'c',
              name: 'read_knowledge_file',
              arguments: <String, dynamic>{'path': 'a.md'},
            ),
          ]),
          LLMMessage(
              role: LLMRole.tool, content: 'ok', toolCallId: 'c', toolName: 'read_knowledge_file'),
        ],
      );

      expect(PromptOptimizerAgent.currentTurnSteps(session), 1);
    });

    test('a turn that has called nothing yet is at zero, not at its predecessor', () {
      final session = PromptOptimizerSession.fromStored(
        id: 's',
        mode: AssistantMode.knowledgeBase,
        history: <LLMMessage>[
          LLMMessage(role: LLMRole.user, content: 'first'),
          LLMMessage(role: LLMRole.assistant, content: '', toolCalls: <LLMToolCall>[
            LLMToolCall(id: 'a', name: 'view_image', arguments: <String, dynamic>{'id': '1'}),
          ]),
          LLMMessage(role: LLMRole.tool, content: 'ok', toolCallId: 'a', toolName: 'view_image'),
          LLMMessage(role: LLMRole.assistant, content: 'done'),
          LLMMessage(role: LLMRole.user, content: 'second'),
        ],
      );

      expect(PromptOptimizerAgent.currentTurnSteps(session), 0);
    });

    test('the run clock starts and stops with the turn', () {
      final session = PromptOptimizerSession();
      expect(session.runStartedAt, isNull);
      session.setRunningForTest(true);
      expect(session.runStartedAt, isNotNull);
      session.setRunningForTest(false);
      // Cleared, not left behind: a stale start would have the next turn's
      // card open at however long the last one took.
      expect(session.runStartedAt, isNull);
    });
  });

  group('staged edits waiting on the user', () {
    PromptOptimizerSession sessionWithEdits() {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      session.stageKbEditForTest(relPath: 'a.md', newContent: 'a', oldContent: 'A');
      session.stageKbEditForTest(relPath: 'b.md', newContent: 'b');
      session.stageKbEditForTest(relPath: 'c.md', newContent: 'c', oldContent: 'C');
      return session;
    }

    test('lists every pending edit in the order it was proposed', () {
      final pending = PromptOptimizerAgent.pendingKbEdits(sessionWithEdits());
      expect(pending.map((e) => e.targetPath), <String>['a.md', 'b.md', 'c.md']);
    });

    test('an answered edit drops out of the list', () {
      final session = sessionWithEdits();
      final id = PromptOptimizerAgent.pendingKbEdits(session)[1].editId!;
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: id);

      final pending = PromptOptimizerAgent.pendingKbEdits(session);
      expect(pending.map((e) => e.targetPath), <String>['a.md', 'c.md']);
    });

    test('a session with nothing staged reports none', () {
      expect(PromptOptimizerAgent.pendingKbEdits(PromptOptimizerSession()), isEmpty);
    });
  });

  group('the composer while a turn runs', () {
    Future<void> pumpChat(
      WidgetTester tester, {
      required bool busy,
      VoidCallback? onAbort,
    }) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ui = WorkbenchUIState();
      ui.optimizerSession = PromptOptimizerSession(mode: AssistantMode.knowledgeBase);

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
              isBusy: busy,
              onAbort: onAbort,
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('idle, the composer sends and says so', (tester) async {
      await pumpChat(tester, busy: false, onAbort: () {});
      final l10n = await en();
      expect(find.text(l10n.optAbort), findsNothing);
      expect(find.text(l10n.optSendHint), findsOneWidget);
    });

    testWidgets('busy, send is replaced by stop and the hint names Esc', (tester) async {
      await pumpChat(tester, busy: true, onAbort: () {});
      final l10n = await en();
      expect(find.text(l10n.optAbort), findsOneWidget);
      expect(find.text(l10n.optAbortHint), findsOneWidget);
      expect(find.text(l10n.optChatBusyHint), findsOneWidget);
    });

    testWidgets('busy with nothing to stop leaves the send button in place', (tester) async {
      // The crashed-turn case: a session whose running flag outlived its task.
      // A stop control there would do nothing when pressed.
      await pumpChat(tester, busy: true, onAbort: null);
      final l10n = await en();
      expect(find.text(l10n.optAbort), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('Esc in the composer stops the turn', (tester) async {
      int stopped = 0;
      await pumpChat(tester, busy: true, onAbort: () => stopped++);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(stopped, 1);
    });

    testWidgets('Esc does nothing when no turn is running', (tester) async {
      int stopped = 0;
      await pumpChat(tester, busy: false, onAbort: () => stopped++);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(stopped, 0);
    });
  });

  group('the system-prompt card', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      required String? text,
      required int? templateId,
      double width = 250,
      void Function(int?, String?)? onTemplateChanged,
    }) async {
      final appState = AppState();
      final templates = <SystemPrompt>[
        SystemPrompt(id: 1, title: 'Photo v3', content: 'BASE', type: 'refiner'),
        SystemPrompt(id: 2, title: 'Product', content: 'OTHER', type: 'refiner'),
      ];

      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            // The width the assistant's right panel narrows to, which is where
            // a picker, a counter row and two buttons have to fit.
            body: SizedBox(
              width: width,
              child: OptimizerConfigPanel(
                selectedModelDbId: null,
                selectedSysPrompt: text,
                sysPromptTemplateId: templateId,
                mode: AssistantMode.systemPrompt,
                kbStatus: KbStatus.notSet,
                sysPrompts: templates,
                onModelChanged: (_) {},
                onSysPromptChanged: (_) {},
                onSysPromptTemplateChanged: onTemplateChanged ?? (_, _) {},
                onSaveTemplate: (_, _) async {},
                onModeChanged: (_) {},
                onScaffoldKb: () async {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('an untouched template offers neither save nor reset', (tester) async {
      await pumpPanel(tester, text: 'BASE', templateId: 1);
      final l10n = await en();

      // Present but inert, so the row keeps its height and the card does not
      // jump the first time a character is typed.
      for (final label in <String>[l10n.optSysPromptSave, l10n.optSysPromptReset]) {
        final button = tester.widget<AppButton>(find.widgetWithText(AppButton, label));
        expect(button.onPressed, isNull, reason: label);
      }
      expect(find.text(l10n.optSysPromptUnsaved), findsNothing);
    });

    testWidgets('editing away from the template says so and enables both', (tester) async {
      await pumpPanel(tester, text: 'BASE and then some', templateId: 1);
      final l10n = await en();

      expect(find.text(l10n.optSysPromptUnsaved), findsOneWidget);
      for (final label in <String>[l10n.optSysPromptSave, l10n.optSysPromptReset]) {
        final button = tester.widget<AppButton>(find.widgetWithText(AppButton, label));
        expect(button.onPressed, isNotNull, reason: label);
      }
    });

    testWidgets('reset hands back the template it came from', (tester) async {
      int? gotId;
      String? gotContent;
      await pumpPanel(
        tester,
        text: 'BASE edited',
        templateId: 1,
        onTemplateChanged: (id, content) {
          gotId = id;
          gotContent = content;
        },
      );
      final l10n = await en();

      await tester.tap(find.text(l10n.optSysPromptReset));
      await tester.pump();

      expect(gotId, 1);
      expect(gotContent, 'BASE');
    });

    testWidgets('the card fits the width the panel narrows to', (tester) async {
      await pumpPanel(tester, text: 'BASE edited', templateId: 1);
      expect(tester.takeException(), isNull);
    });
  });
}
