import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/assistant_note_repository.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

/// Everything one turn persists goes to the database [PromptOptimizerAgent.runTurn]
/// was given: the session and its messages, and the sub-agent notes the
/// `delegate` tool writes and `read_note` pages back.
///
/// The notes matter as much as the session rows because a note carries a
/// `session_id`: a turn whose session lands in one database and whose notes
/// land in another leaves `read_note` unable to find what `delegate` just
/// saved, and no error is raised — the tool simply answers "no note in this
/// conversation".
///
/// These tests deliberately do **not** call `usePrivateDataDir`: with no
/// path_provider behind it the default [DatabaseService] cannot open at all,
/// so a row that escapes to the singleton cannot land in the app's real file.
/// It does not fail loudly either — the turn swallows persistence errors — so
/// what catches an escape is the positive assertion on the injected database.
void main() {
  sqfliteFfiInit();

  late DatabaseService db;
  late Directory tmp;

  setUp(() async {
    db = await openTestDatabase();
    tmp = Directory.systemTemp.createTempSync('optimizer_turn_db_');
  });
  tearDown(() async {
    PromptOptimizerAgent.debugRequestOverride = null;
    await closeTestDatabase(db);
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle; systemTemp is reaped by the OS.
    }
  });

  /// A reference image on disk, which is what makes the `draft` delegate kind
  /// available — and `read_note` is offered alongside every delegate kind.
  List<Map<String, String>> oneReference() {
    final file = File('${tmp.path}${Platform.pathSeparator}ref.png')
      ..writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    return [
      {'path': file.path, 'name': 'ref.png'},
    ];
  }

  test('read_note reads the note store of the database the turn was given',
      () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');

    final note = await AssistantNoteRepository(db: db).insert(
      sessionId: session.id,
      title: 'Findings',
      content: 'the sub-agent found a teal gradient',
    );

    var requests = 0;
    List<LLMMessage>? followUp;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      if (requests == 1) {
        expect(tools!.map((t) => t.name), contains('read_note'));
        return LLMResponse(text: '', toolCalls: [
          LLMToolCall(id: 'n1', name: 'read_note', arguments: {'note_id': note.id}),
        ]);
      }
      followUp = List.of(messages);
      return LLMResponse(text: 'ok');
    };

    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: oneReference(),
      kbSubAgentEnabled: true,
      database: db,
    );

    final result = followUp!.lastWhere((m) => m.role == LLMRole.tool);
    final decoded = jsonDecode(result.content) as Map;
    expect(decoded['status'], isNot('error'),
        reason: 'the note store must be the injected database: $decoded');
    expect(decoded['content'], contains('teal gradient'));
  });

  test('the session and its messages land in the injected database', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');

    PromptOptimizerAgent.debugRequestOverride =
        (messages, tools, options) async => LLMResponse(text: 'ok');

    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
      database: db,
    );

    final raw = await db.database;
    final sessions = await raw.query('assistant_sessions',
        where: 'id = ?', whereArgs: [session.id]);
    expect(sessions, hasLength(1));
    final messages = await raw.query('assistant_messages',
        where: 'session_id = ?', whereArgs: [session.id]);
    expect(messages, isNotEmpty);
  });
}
