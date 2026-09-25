import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// Standard 08 §3.6: staged edit cards do not block the turn, so the model
/// learns what the user did with them only if something tells it. The next
/// turn opens with a short factual record of the outcomes since the last one.
void main() {
  usePrivateDataDir('joycai_kb_edit_outcomes_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  test('decided edits are reported once, at the start of the next turn', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('first');
    final applied = session.stageKbEditForTest(
      relPath: 'rules/a.md',
      newContent: 'new',
      oldContent: 'old',
    );
    final rejected = session.stageKbEditForTest(
      relPath: 'rules/b.md',
      newContent: 'new',
      oldContent: null,
    );
    session.stageKbEditForTest(relPath: 'rules/c.md', newContent: 'new', oldContent: 'old');
    session.resolveKbEditForTest(applied, KbEditState.applied);
    session.resolveKbEditForTest(rejected, KbEditState.rejected);

    List<LLMMessage>? sent;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      sent = List.of(messages);
      return LLMResponse(text: 'ok');
    };

    session.addUserTurn('second');
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
    );

    final note = sent!.last;
    expect(note.role, LLMRole.user);
    expect(note.content, contains('rules/a.md'));
    expect(note.content, contains('applied'));
    expect(note.content, contains('rules/b.md'));
    expect(note.content, contains('rejected'));
    expect(
      note.content,
      isNot(contains('rules/c.md')),
      reason: 'still pending — nothing to report',
    );

    session.addUserTurn('third');
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
    );
    expect(sent!.last.content, 'third', reason: 'already reported outcomes are not repeated');
  });

  test('the record stays in the history but is neither a chat line nor a user turn', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('first');
    final id = session.stageKbEditForTest(
      relPath: 'rules/a.md',
      newContent: 'new',
      oldContent: 'old',
    );
    session.resolveKbEditForTest(id, KbEditState.rejected);
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async =>
        LLMResponse(text: 'ok');

    session.addUserTurn('second');
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'm',
      referenceImages: const [],
    );

    expect(
      session.history.where((m) => m.content.contains('rules/a.md')),
      hasLength(1),
      reason: 'persisted with the turn, so later requests keep the same prefix',
    );

    final restored = PromptOptimizerSession.fromStored(
      id: session.id,
      mode: session.mode,
      history: List.of(session.history),
    );
    expect(restored.transcript.where((e) => e.kind == OptimizerEntryKind.user).map((e) => e.text), [
      'first',
      'second',
    ]);
  });
}
