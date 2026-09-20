// `A3d 4d`: a knowledge session moves between writing prompts and
// maintaining the base without becoming another conversation — and nothing
// else about a session's mode may move.
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/assistant_session_repository.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

void main() {
  usePrivateDataDir('joycai_kb_use_switch_test');
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('WorkbenchUIState.setAssistantMode', () {
    test('between the knowledge uses it keeps the session and notifies', () async {
      final ui = WorkbenchUIState()
        ..optimizerSession = PromptOptimizerSession(mode: AssistantMode.knowledgeBase);
      final session = ui.optimizerSession..addUserTurn('x');
      var notified = 0;
      ui.addListener(() => notified++);

      ui.setAssistantMode(AssistantMode.knowledgeEdit);
      expect(identical(ui.optimizerSession, session), isTrue);
      expect(ui.assistantMode, AssistantMode.knowledgeEdit);
      expect(notified, 1);
      // Let the fire-and-forget mode write finish before the data dir goes.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('a refused switch does not fall through to a new session', () {
      final ui = WorkbenchUIState()
        ..optimizerSession = PromptOptimizerSession(mode: AssistantMode.knowledgeBase);
      final session = ui.optimizerSession..setRunningForTest(true);

      ui.setAssistantMode(AssistantMode.knowledgeEdit);
      expect(identical(ui.optimizerSession, session), isTrue);
      expect(ui.assistantMode, AssistantMode.knowledgeBase);
    });

    test('across the basis it is still a new session', () {
      final ui = WorkbenchUIState()
        ..optimizerSession = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      final session = ui.optimizerSession;

      ui.setAssistantMode(AssistantMode.systemPrompt);
      expect(identical(ui.optimizerSession, session), isFalse);
      expect(ui.assistantMode, AssistantMode.systemPrompt);
    });
  });

  group('switchKnowledgeUse', () {
    test('keeps the session, its history and its transcript, and says so once', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase)
        ..addUserTurn('write me a prompt');
      final historyBefore = session.history.length;

      expect(session.switchKnowledgeUse(AssistantMode.knowledgeEdit), isTrue);
      expect(session.mode, AssistantMode.knowledgeEdit);
      expect(session.canWriteKnowledge, isTrue);
      // A fact about the interface, not something said to the model.
      expect(session.history.length, historyBefore);
      expect(session.transcript.last.text, PromptOptimizerAgent.kbUseMaintainNoticeToken);
    });

    test('back to writing prompts withdraws the write tools', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit)
        ..addUserTurn('fix the footwear page');
      expect(session.switchKnowledgeUse(AssistantMode.knowledgeBase), isTrue);
      // `editMode` in runTurn is exactly this getter.
      expect(session.canWriteKnowledge, isFalse);
    });

    test('edits staged before the switch stay answerable after it', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit)
        ..addUserTurn('x');
      session.stageKbEditForTest(relPath: 'a.md', newContent: 'a', oldContent: 'A');
      session.switchKnowledgeUse(AssistantMode.knowledgeBase);

      final pending = PromptOptimizerAgent.pendingKbEdits(session);
      expect(pending, hasLength(1));
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: pending.single.editId!);
      expect(PromptOptimizerAgent.pendingKbEdits(session), isEmpty);
    });

    test('toggling with nothing said in between leaves one divider, the latest', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase)
        ..addUserTurn('x');
      session.switchKnowledgeUse(AssistantMode.knowledgeEdit);
      final length = session.transcript.length;
      session.switchKnowledgeUse(AssistantMode.knowledgeBase);

      expect(session.transcript.length, length);
      expect(session.transcript.last.text, PromptOptimizerAgent.kbUseWriteNoticeToken);
    });

    test('an empty conversation gets no divider, but still notifies', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase);
      var notified = 0;
      session.addListener(() => notified++);

      expect(session.switchKnowledgeUse(AssistantMode.knowledgeEdit), isTrue);
      expect(session.transcript, isEmpty);
      expect(notified, 1);
    });

    test('hands out a new transcript list rather than growing the old one', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase)
        ..addUserTurn('x');
      final before = session.transcript;
      session.switchKnowledgeUse(AssistantMode.knowledgeEdit);
      expect(identical(before, session.transcript), isFalse);
      session.switchKnowledgeUse(AssistantMode.knowledgeBase);
      expect(before, hasLength(1));
    });

    test('is refused while a turn runs', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase)
        ..setRunningForTest(true);
      expect(session.switchKnowledgeUse(AssistantMode.knowledgeEdit), isFalse);
      expect(session.mode, AssistantMode.knowledgeBase);
    });

    test('is refused across the basis, both ways', () {
      final preset = PromptOptimizerSession();
      expect(preset.switchKnowledgeUse(AssistantMode.knowledgeBase), isFalse);
      expect(preset.mode, AssistantMode.systemPrompt);

      final kb = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      expect(kb.switchKnowledgeUse(AssistantMode.systemPrompt), isFalse);
      expect(kb.mode, AssistantMode.knowledgeEdit);
    });

    test('the write policy still overrides maintenance after a switch', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase)
        ..writePolicy = const KbWritePolicy(allowWrites: false);
      session.switchKnowledgeUse(AssistantMode.knowledgeEdit);
      expect(session.canWriteKnowledge, isFalse);
    });
  });

  group('the stored mode follows the session', () {
    late Database db;
    late AssistantSessionRepository repo;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: DatabaseService.dbVersion,
          onCreate: (db, version) => DatabaseMigration.onCreate(db),
        ),
      );
      repo = AssistantSessionRepository(dbProvider: () async => db);
    });

    tearDown(() async => db.close());

    test('a later sync writes the mode the session has by then', () async {
      await repo.upsertSession(id: 's', mode: AssistantMode.knowledgeBase, refImages: const []);
      await repo.upsertSession(id: 's', mode: AssistantMode.knowledgeEdit, refImages: const []);
      expect((await repo.getSession('s'))!.mode, AssistantMode.knowledgeEdit);
    });

    test('a switch is recorded at once, and a session with no row is left alone', () async {
      await repo.upsertSession(id: 's', mode: AssistantMode.knowledgeEdit, refImages: const []);
      await repo.setSessionMode('s', AssistantMode.knowledgeBase);
      expect((await repo.getSession('s'))!.mode, AssistantMode.knowledgeBase);

      await repo.setSessionMode('never-synced', AssistantMode.knowledgeEdit);
      expect(await repo.getSession('never-synced'), isNull);
    });
  });
}
