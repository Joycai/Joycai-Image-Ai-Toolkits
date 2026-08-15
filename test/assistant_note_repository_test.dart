import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/database_migrations.dart';
import 'package:joycai_image_ai_toolkits/services/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/repositories/assistant_note_repository.dart';
import 'package:joycai_image_ai_toolkits/services/repositories/assistant_session_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pins the M3.2 note store (assistant_notes, v34): slug hygiene, session
/// scoping, collision handling, the retention path, and the elide rule that
/// keeps read_note results from re-flooding the context they exist to spare.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late Database db;
  late AssistantNoteRepository notes;

  Future<Database> provider() async => db;

  setUp(() async {
    db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseService.dbVersion,
        onCreate: (db, version) => DatabaseMigration.onCreate(db),
      ),
    );
    notes = AssistantNoteRepository(dbProvider: provider);
  });

  tearDown(() async => db.close());

  group('sanitizeSlug', () {
    test('keeps letters and digits of any script', () {
      // An ASCII whitelist would collapse every CJK title into ''.
      expect(AssistantNoteRepository.sanitizeSlug('角色设定 规则 v2'),
          '角色设定-规则-v2');
    });

    test('collapses runs and trims edge dashes', () {
      expect(AssistantNoteRepository.sanitizeSlug('  a//b__c  '), 'a-b-c');
    });

    test('caps at 60 code points and never returns empty', () {
      expect(AssistantNoteRepository.sanitizeSlug('好' * 80).runes.length, 60);
      expect(AssistantNoteRepository.sanitizeSlug('!!!'), 'note');
    });
  });

  group('insert / get', () {
    test('round-trips a note within its session', () async {
      final note = await notes.insert(
          sessionId: 's1', title: '查一下构图规则', content: 'findings text');
      expect(note.id, greaterThan(0));
      final loaded = await notes.get(note.id, sessionId: 's1');
      expect(loaded!.content, 'findings text');
      expect(loaded.slug, '查一下构图规则');
    });

    test('a note id from another session reads as not-found', () async {
      // Reading a note nobody in this conversation commissioned is worse
      // than not finding it.
      final note = await notes.insert(
          sessionId: 's1', title: 't', content: 'secret');
      expect(await notes.get(note.id, sessionId: 's2'), isNull);
    });

    test('slug collisions get suffixes, never an overwrite', () async {
      final a = await notes.insert(sessionId: 's1', title: '规则', content: 'a');
      final b = await notes.insert(sessionId: 's1', title: '规则', content: 'b');
      final c = await notes.insert(sessionId: 's1', title: '规则', content: 'c');
      expect(a.slug, '规则');
      expect(b.slug, '规则-2');
      expect(c.slug, '规则-3');
      expect((await notes.get(a.id, sessionId: 's1'))!.content, 'a');
    });

    test('oversize content is truncated with a visible marker', () async {
      final note = await notes.insert(
        sessionId: 's1',
        title: 'big',
        content: 'x' * (AssistantNoteRepository.maxContentChars + 100),
      );
      expect(note.content.length,
          lessThan(AssistantNoteRepository.maxContentChars + 100));
      expect(note.content, contains('[note truncated'));
    });

    test('listForSession returns only that session, oldest first', () async {
      await notes.insert(sessionId: 's1', title: 'a', content: '1');
      await notes.insert(sessionId: 's2', title: 'x', content: '2');
      await notes.insert(sessionId: 's1', title: 'b', content: '3');
      final list = await notes.listForSession('s1');
      expect([for (final n in list) n.title], ['a', 'b']);
    });
  });

  group('retention', () {
    test('deleteSession removes the session\'s notes with it', () async {
      final sessions = AssistantSessionRepository(dbProvider: provider);
      await sessions.upsertSession(
          id: 's1', mode: AssistantMode.knowledgeBase, refImages: const []);
      final note =
          await notes.insert(sessionId: 's1', title: 't', content: 'c');
      await notes.insert(sessionId: 'other', title: 't', content: 'kept');

      await sessions.deleteSession('s1');

      expect(await notes.get(note.id, sessionId: 's1'), isNull);
      expect(await notes.listForSession('other'), hasLength(1));
    });
  });

  group('read_note elision', () {
    test('bulky read_note results elide exactly like knowledge reads', () {
      final elided = PromptOptimizerAgent.elideForTest(LLMMessage(
        role: LLMRole.tool,
        content: jsonEncode({'note_id': 1, 'content': 'x' * 500}),
        toolCallId: 'c1',
        toolName: 'read_note',
      ));
      expect(elided.content, contains('Content elided'));
      // Pairing survives: only the content is swapped.
      expect(elided.toolCallId, 'c1');
      expect(elided.toolName, 'read_note');
    });

    test('small results and other tools pass through untouched', () {
      final small = LLMMessage(
        role: LLMRole.tool,
        content: '{"status":"ok"}',
        toolCallId: 'c1',
        toolName: 'read_note',
      );
      expect(PromptOptimizerAgent.elideForTest(small).content, small.content);
    });
  });
}
