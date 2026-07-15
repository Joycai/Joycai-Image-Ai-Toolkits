import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';

/// Covers the knowledge-edit surface: the staged-edit approval card, and the
/// three-way mode selector.
///
/// The card is the last line of defense before an LLM-authored rewrite lands on
/// the user's knowledge base, so these pin that a pending edit always offers
/// both actions, that a resolved one offers neither, and that a suspiciously
/// truncated rewrite is called out.
void main() {
  const breakpoints = <String, Size>{
    'Mobile': Size(360, 800),
    'Tablet': Size(800, 1000),
    'Desktop': Size(1400, 1000),
  };

  Future<void> pumpChat(WidgetTester tester, PromptOptimizerSession session,
      {Size size = const Size(1400, 1000),
      void Function(String)? onApply,
      void Function(String)? onReject}) async {
    tester.view.physicalSize = size;
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
            onApplyKbEdit: onApply ?? (_) {},
            onRejectKbEdit: onReject ?? (_) {},
            isBusy: false,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('staged edit card', () {
    testWidgets('a pending edit offers both approve and discard', (tester) async {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final id = session.stageKbEditForTest(
        relPath: 'templates/text-to-image.md',
        newContent: '# 文生图\n\n补充了镜头语言的说明。',
        oldContent: '# 文生图\n',
      );
      expect(id, isNotEmpty);

      String? applied;
      await pumpChat(tester, session, onApply: (e) => applied = e);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text('templates/text-to-image.md'), findsOneWidget);
      expect(find.text(l10n.kbEditProposedUpdate), findsOneWidget);
      expect(find.text(l10n.kbEditApply), findsOneWidget);
      expect(find.text(l10n.kbEditReject), findsOneWidget);

      await tester.tap(find.text(l10n.kbEditApply));
      expect(applied, id);
    });

    test('rejecting flips the card without touching the read cache', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      session.readKnowledgePages.add('a.md#1');
      final id = session.stageKbEditForTest(
        relPath: 'a.md',
        newContent: 'new',
        oldContent: 'old',
      );

      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: id);

      final entry = session.transcript.firstWhere((e) => e.editId == id);
      expect(entry.editState, KbEditState.rejected);
      // The file never changed, so a re-read would still be redundant.
      expect(session.readKnowledgePages, contains('a.md#1'));
    });

    test('rejecting twice is a no-op rather than an error', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final id = session.stageKbEditForTest(relPath: 'a.md', newContent: 'x', oldContent: null);
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: id);
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: id);
      expect(
        session.transcript.where((e) => e.editState == KbEditState.rejected),
        hasLength(1),
      );
    });

    testWidgets('a new file is labelled as a create, not an update', (tester) async {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      session.stageKbEditForTest(
        relPath: 'conditional/new-rule.md',
        newContent: '# 新规则',
        oldContent: null,
      );
      await pumpChat(tester, session);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.kbEditProposedCreate), findsOneWidget);
      expect(find.text(l10n.kbEditProposedUpdate), findsNothing);
    });

    testWidgets('a resolved edit offers no actions', (tester) async {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final id = session.stageKbEditForTest(relPath: 'a.md', newContent: 'x', oldContent: null);
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: id);
      await pumpChat(tester, session);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.kbEditRejected), findsOneWidget);
      expect(find.text(l10n.kbEditApply), findsNothing);
      expect(find.text(l10n.kbEditReject), findsNothing);
    });

    testWidgets('content is collapsed by default and expands on demand', (tester) async {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      const body = '# 文生图\nUNIQUE_BODY_MARKER\n';
      session.stageKbEditForTest(relPath: 'a.md', newContent: body, oldContent: null);
      await pumpChat(tester, session);

      // A knowledge file can run to thousands of characters; it must not bury
      // the conversation before the user asks for it.
      expect(find.textContaining('UNIQUE_BODY_MARKER'), findsNothing);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.kbEditShow(body.length)));
      await tester.pumpAndSettle();
      expect(find.textContaining('UNIQUE_BODY_MARKER'), findsOneWidget);
    });

    testWidgets('a rewrite that halves the file is flagged', (tester) async {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      session.stageKbEditForTest(
        relPath: 'a.md',
        newContent: 'x' * 50,
        oldContent: 'y' * 1000,
      );
      await pumpChat(tester, session);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    });

    testWidgets('a comparable rewrite is not flagged', (tester) async {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      session.stageKbEditForTest(
        relPath: 'a.md',
        newContent: 'x' * 900,
        oldContent: 'y' * 1000,
      );
      await pumpChat(tester, session);
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    });

    for (final entry in breakpoints.entries) {
      testWidgets('lays out without overflow on ${entry.key}', (tester) async {
        final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
        session.stageKbEditForTest(
          relPath: 'templates/a-fairly-long-knowledge-file-name.md',
          newContent: '# 标题\n' * 40,
          oldContent: '# 标题\n',
          note: '补充了镜头语言与光线的说明，并同步更新了文件地图。',
        );
        await pumpChat(tester, session, size: entry.value);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('restored sessions', () {
    test('a write replays as a plain chip, never as an actionable card', () {
      // The approval outcome is not persisted and oldContent would be stale, so
      // re-offering Apply after a restart could clobber newer content.
      final session = PromptOptimizerSession.fromStored(
        id: 'opt_restore',
        mode: AssistantMode.knowledgeEdit,
        history: [
          LLMMessage(role: LLMRole.user, content: '给模板补充镜头语言'),
          LLMMessage(
            role: LLMRole.assistant,
            content: '',
            toolCalls: [
              LLMToolCall(
                id: 'c1',
                name: 'write_knowledge_file',
                arguments: {'path': 'templates/text-to-image.md', 'content': '# 文生图'},
              ),
            ],
          ),
        ],
      );

      final chips = session.transcript.where((e) => e.toolName == 'write_knowledge_file');
      expect(chips, hasLength(1));
      expect(chips.single.kind, OptimizerEntryKind.tool);
      expect(chips.single.text, 'templates/text-to-image.md');
      expect(session.transcript.any((e) => e.kind == OptimizerEntryKind.kbEdit), isFalse);
    });
  });

  group('mode predicates', () {
    test('both knowledge modes require a knowledge base', () {
      expect(PromptOptimizerSession(mode: AssistantMode.knowledgeBase).usesKnowledgeBase, isTrue);
      expect(PromptOptimizerSession(mode: AssistantMode.knowledgeEdit).usesKnowledgeBase, isTrue);
      expect(PromptOptimizerSession(mode: AssistantMode.systemPrompt).usesKnowledgeBase, isFalse);
    });

    test('only the edit mode may write', () {
      expect(PromptOptimizerSession(mode: AssistantMode.knowledgeEdit).canWriteKnowledge, isTrue);
      expect(PromptOptimizerSession(mode: AssistantMode.knowledgeBase).canWriteKnowledge, isFalse);
      expect(PromptOptimizerSession(mode: AssistantMode.systemPrompt).canWriteKnowledge, isFalse);
    });
  });

  group('knowledge base status', () {
    test('an empty folder reports a missing entry, which scaffolding resolves', () async {
      expect(await KnowledgeBaseService().validate('/definitely/not/a/real/path'),
          KbStatus.missingDir);
    });
  });
}
