import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// Pins `repairToolCallPairing` (standard 07 §3.2, 10 §4.3): a restored or
/// interrupted history must come back sendable, because an unanswered call or
/// an orphan result 400s every later request of the session.
void main() {
  LLMMessage user(String text) => LLMMessage(role: LLMRole.user, content: text);

  LLMMessage assistantCalls(List<String> ids, {String name = 'list_reference_images', String content = ''}) =>
      LLMMessage(
        role: LLMRole.assistant,
        content: content,
        toolCalls: [
          for (final id in ids) LLMToolCall(id: id, name: name, arguments: const {}),
        ],
      );

  LLMMessage result(String id, {String name = 'list_reference_images'}) => LLMMessage(
        role: LLMRole.tool,
        content: '{"status":"ok"}',
        toolCallId: id,
        toolName: name,
      );

  const validQuestions = {
    'questions': [
      {
        'header': 'Style',
        'question': 'Which style?',
        'options': [
          {'label': 'A'},
          {'label': 'B'},
        ],
      },
    ],
  };

  List<LLMMessage> repair(List<LLMMessage> h) => PromptOptimizerAgent.repairToolCallPairing(h);

  test('an intact history comes back as the same objects', () {
    final h = [user('go'), assistantCalls(['a']), result('a'), user('next')];
    final out = repair(h);
    expect(out, hasLength(h.length));
    for (var i = 0; i < h.length; i++) {
      expect(identical(out[i], h[i]), isTrue);
    }
  });

  test('an unanswered call gets a [not run] stub at the end of its batch', () {
    // A dropped tool row: call b lost its result.
    final out = repair([user('go'), assistantCalls(['a', 'b']), result('a'), user('next')]);
    expect(out.map((m) => m.role), [
      LLMRole.user,
      LLMRole.assistant,
      LLMRole.tool,
      LLMRole.tool,
      LLMRole.user,
    ]);
    expect(out[2].toolCallId, 'a');
    expect(out[3].toolCallId, 'b');
    expect(out[3].toolName, 'list_reference_images');
    expect(jsonDecode(out[3].content)['message'], startsWith('[not run]'));
  });

  test('results orphaned by a dropped assistant row are dropped', () {
    final out = repair([user('go'), result('a'), result('b'), user('next')]);
    expect(out.map((m) => m.role), [LLMRole.user, LLMRole.user]);
  });

  test('a result outside its batch, or a duplicate, is dropped', () {
    final out = repair([
      user('go'),
      assistantCalls(['a']),
      result('a'),
      result('a'), // duplicate
      user('view'),
      result('a'), // not adjacent to its call
    ]);
    expect(out.map((m) => m.role),
        [LLMRole.user, LLMRole.assistant, LLMRole.tool, LLMRole.user]);
  });

  test('calls with empty ids are stripped, and an emptied assistant is dropped', () {
    final out = repair([
      user('go'),
      assistantCalls(['']),
      result(''),
      assistantCalls(['', 'k'], content: 'thinking aloud'),
      result('k'),
    ]);
    expect(out.map((m) => m.role), [LLMRole.user, LLMRole.assistant, LLMRole.tool]);
    expect(out[1].toolCalls.single.id, 'k');
    expect(out[1].content, 'thinking aloud');
  });

  test('an assistant message with neither text nor calls is dropped', () {
    final out = repair([user('go'), LLMMessage(role: LLMRole.assistant, content: '  ')]);
    expect(out.map((m) => m.role), [LLMRole.user]);
  });

  test('a trailing valid ask_user stays dangling — the suspended question', () {
    final ask = LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [LLMToolCall(id: 'q1', name: 'ask_user', arguments: validQuestions)],
    );
    final out = repair([user('go'), ask]);
    expect(out, hasLength(2));

    final restored = PromptOptimizerSession.fromStored(
      id: 's',
      mode: AssistantMode.systemPrompt,
      history: [user('go'), ask],
    );
    expect(restored.pendingAskUser?.callId, 'q1');
  });

  test('a non-trailing unanswered ask_user is stubbed and restores dismissed', () {
    final ask = LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [LLMToolCall(id: 'q1', name: 'ask_user', arguments: validQuestions)],
    );
    final restored = PromptOptimizerSession.fromStored(
      id: 's',
      mode: AssistantMode.systemPrompt,
      history: [user('go'), ask, user('never mind')],
    );
    expect(restored.pendingAskUser, isNull);
    expect(restored.history[2].toolCallId, 'q1');
    final card = restored.transcript.firstWhere((e) => e.kind == OptimizerEntryKind.askUser);
    expect(card.askState, AskUserState.dismissed);
  });

  test('repair is idempotent', () {
    final broken = [
      user('go'),
      result('x'),
      assistantCalls(['a', 'b']),
      result('b'),
      user('next'),
      assistantCalls(['']),
    ];
    final once = repair(broken);
    final twice = repair(once);
    expect(twice, hasLength(once.length));
    for (var i = 0; i < once.length; i++) {
      expect(identical(twice[i], once[i]), isTrue);
    }
  });

  test('fromStored hands out the repaired history, all of it counted persisted', () {
    final restored = PromptOptimizerSession.fromStored(
      id: 's',
      mode: AssistantMode.systemPrompt,
      history: [user('go'), assistantCalls(['a', 'b']), result('a'), user('next')],
    );
    expect(restored.history, hasLength(5));
    expect(restored.persistedCount, 5);
  });
}
