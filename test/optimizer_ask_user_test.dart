import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// The ask_user tool suspends the agent turn with a deliberately dangling
/// tool call — its result IS the user's answer. These tests pin the three
/// properties that keep that safe:
///
///  1. pending-ness is *derived* from the history (never a flag), so live and
///     restored sessions behave identically;
///  2. every path back into a turn pairs the call first (answer, free text,
///     or the self-healing cancel guard), so an unpaired call can never be
///     sent to a provider; and
///  3. the strict argument parser rejects malformed payloads so a broken
///     question can never become an unanswerable card.
void main() {
  const validQuestions = [
    {
      'header': '鞋型',
      'question': '参考图的鞋子是哪种类型？',
      'options': [
        {'label': '一体袜靴', 'description': '袜子和鞋底一体'},
        {'label': '普通短靴'},
      ],
    },
  ];

  PromptOptimizerSession newSession() =>
      PromptOptimizerSession(mode: AssistantMode.systemPrompt);

  /// Appends the assistant message carrying a (dangling) ask_user call,
  /// matching the shape runTurn leaves behind when it suspends.
  String recordAsk(PromptOptimizerSession session,
      {Object? questions = validQuestions}) {
    final callId = 'call_${session.history.length}';
    session.history.add(LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [
        LLMToolCall(
          id: callId,
          name: 'ask_user',
          arguments: {'questions': questions},
        ),
      ],
    ));
    return callId;
  }

  group('AskUserQuestion.tryParse', () {
    test('accepts a valid payload, including quoted multi_select', () {
      final parsed = AskUserQuestion.tryParse([
        {
          'header': 'H',
          'question': 'Q?',
          'multi_select': 'true',
          'options': [
            {'label': 'a', 'description': 'why a'},
            {'label': 'b'},
            {'label': 'c'},
            {'label': 'd'},
          ],
        },
      ]);
      expect(parsed, isNotNull);
      expect(parsed!.single.multiSelect, isTrue);
      expect(parsed.single.options, hasLength(4));
      expect(parsed.single.options.first.description, 'why a');
      expect(parsed.single.options[1].description, isNull);
    });

    test('multi_select defaults to false', () {
      final parsed = AskUserQuestion.tryParse(validQuestions);
      expect(parsed!.single.multiSelect, isFalse);
    });

    test('rejects empty, oversized, and non-list payloads', () {
      expect(AskUserQuestion.tryParse(null), isNull);
      expect(AskUserQuestion.tryParse('questions'), isNull);
      expect(AskUserQuestion.tryParse([]), isNull);
      expect(
        AskUserQuestion.tryParse(List.filled(5, validQuestions.first)),
        isNull,
      );
    });

    test('rejects option counts outside 2-4 and blank strings', () {
      Map<String, Object> question({List<Object>? options, String header = 'H'}) => {
            'header': header,
            'question': 'Q?',
            'options': options ??
                [
                  {'label': 'a'},
                  {'label': 'b'},
                ],
          };
      expect(
        AskUserQuestion.tryParse([
          question(options: [{'label': 'only one'}]),
        ]),
        isNull,
      );
      expect(
        AskUserQuestion.tryParse([
          question(options: List.filled(5, {'label': 'x'})),
        ]),
        isNull,
      );
      expect(AskUserQuestion.tryParse([question(header: '  ')]), isNull);
      expect(
        AskUserQuestion.tryParse([
          question(options: [
            {'label': 'a'},
            {'label': '   '},
          ]),
        ]),
        isNull,
      );
    });
  });

  group('pendingAskUser derivation', () {
    test('a dangling trailing call is pending', () {
      final session = newSession();
      session.addUserTurn('优化提示词');
      final callId = recordAsk(session);

      final pending = session.pendingAskUser;
      expect(pending, isNotNull);
      expect(pending!.callId, callId);
      expect(pending.questions.single.header, '鞋型');
    });

    test('a paired call is not pending', () {
      final session = newSession();
      session.addUserTurn('go');
      final callId = recordAsk(session);
      session.history.add(LLMMessage(
        role: LLMRole.tool,
        content: jsonEncode({'status': 'ok', 'answers': []}),
        toolCallId: callId,
        toolName: 'ask_user',
      ));

      expect(session.pendingAskUser, isNull);
    });

    test('an answered question followed by more conversation stays resolved', () {
      final session = newSession();
      session.addUserTurn('go');
      final callId = recordAsk(session);
      PromptOptimizerAgent.answerAskUser(
        session: session,
        callId: callId,
        answers: const [AskUserAnswer(header: '鞋型', selected: ['一体袜靴'])],
      );
      session.history.add(LLMMessage(role: LLMRole.assistant, content: 'ok, thanks'));
      session.addUserTurn('再改一下');

      expect(session.pendingAskUser, isNull);
    });

    test('within one batch, an error-answered duplicate does not mask the pending call', () {
      final session = newSession();
      session.addUserTurn('go');
      // One assistant message carrying two ask_user calls: the first was
      // malformed and error-answered immediately (D6), the second is live.
      session.history.add(LLMMessage(
        role: LLMRole.assistant,
        content: '',
        toolCalls: [
          LLMToolCall(id: 'bad', name: 'ask_user', arguments: {'questions': []}),
          LLMToolCall(id: 'good', name: 'ask_user', arguments: {'questions': validQuestions}),
        ],
      ));
      session.history.add(LLMMessage(
        role: LLMRole.tool,
        content: jsonEncode({'status': 'error', 'message': 'invalid'}),
        toolCallId: 'bad',
        toolName: 'ask_user',
      ));

      expect(session.pendingAskUser?.callId, 'good');
    });
  });

  group('answering', () {
    test('answerAskUser appends a correctly paired tool result and flips the card', () {
      final session = newSession();
      session.addUserTurn('go');
      final callId = recordAsk(session);
      // The staged card, as _stageAskUser would have left it.
      expect(session.pendingAskUser, isNotNull);

      PromptOptimizerAgent.answerAskUser(
        session: session,
        callId: callId,
        answers: const [
          AskUserAnswer(header: '鞋型', selected: ['一体袜靴'], otherText: '硬底'),
        ],
      );

      final result = session.history.last;
      expect(result.role, LLMRole.tool);
      expect(result.toolCallId, callId);
      expect(result.toolName, 'ask_user');
      final decoded = jsonDecode(result.content) as Map;
      expect(decoded['status'], 'ok');
      final answer = (decoded['answers'] as List).single as Map;
      expect(answer['header'], '鞋型');
      expect(answer['selected'], ['一体袜靴']);
      expect(answer['other'], '硬底');
      expect(session.pendingAskUser, isNull);
    });

    test('answerAskUser no-ops on a stale callId', () {
      final session = newSession();
      session.addUserTurn('go');
      recordAsk(session);
      final lengthBefore = session.history.length;

      PromptOptimizerAgent.answerAskUser(
        session: session,
        callId: 'not_the_pending_one',
        answers: const [AskUserAnswer(header: 'x', selected: ['y'])],
      );

      expect(session.history.length, lengthBefore);
      expect(session.pendingAskUser, isNotNull);
    });

    test('resolvePendingAskUserAsFreeText pairs the call without answers', () {
      final session = newSession();
      session.addUserTurn('go');
      final callId = recordAsk(session);

      PromptOptimizerAgent.resolvePendingAskUserAsFreeText(
        session: session,
        callId: callId,
      );

      final result = session.history.last;
      expect(result.role, LLMRole.tool);
      expect(result.toolCallId, callId);
      final decoded = jsonDecode(result.content) as Map;
      expect(decoded['status'], 'ok');
      expect(decoded.containsKey('answers'), isFalse);
      expect(session.pendingAskUser, isNull);
    });

    test('the self-healing guard cancels a dangling call', () {
      final session = newSession();
      session.addUserTurn('go');
      final callId = recordAsk(session);

      PromptOptimizerAgent.cancelDanglingAskUserForTest(session);

      final result = session.history.last;
      expect(result.role, LLMRole.tool);
      expect(result.toolCallId, callId);
      expect((jsonDecode(result.content) as Map)['status'], 'cancelled');
      expect(session.pendingAskUser, isNull);
      // Idempotent: nothing left to cancel.
      final lengthBefore = session.history.length;
      PromptOptimizerAgent.cancelDanglingAskUserForTest(session);
      expect(session.history.length, lengthBefore);
    });
  });

  group('fromStored', () {
    test('a dangling call restores as a pending, actionable card', () {
      final live = newSession();
      live.addUserTurn('go');
      recordAsk(live);
      // Round-trip through JSON like the repository does.
      final restoredHistory = [
        for (final m in live.history) LLMMessage.fromJson(m.toJson()),
      ];

      final restored = PromptOptimizerSession.fromStored(
        id: 'restored',
        mode: AssistantMode.systemPrompt,
        history: restoredHistory,
      );

      final card = restored.transcript
          .singleWhere((e) => e.kind == OptimizerEntryKind.askUser);
      expect(card.askState, AskUserState.pending);
      expect(card.askQuestions!.single.header, '鞋型');
      // Actionable: the same pendingAskUser/answerAskUser path works.
      final pending = restored.pendingAskUser;
      expect(pending, isNotNull);
      PromptOptimizerAgent.answerAskUser(
        session: restored,
        callId: pending!.callId,
        answers: const [AskUserAnswer(header: '鞋型', selected: ['普通短靴'])],
      );
      expect(restored.pendingAskUser, isNull);
    });

    test('an answered call restores as a collapsed answered card', () {
      final live = newSession();
      live.addUserTurn('go');
      final callId = recordAsk(live);
      PromptOptimizerAgent.answerAskUser(
        session: live,
        callId: callId,
        answers: const [AskUserAnswer(header: '鞋型', selected: ['一体袜靴'])],
      );
      final restored = PromptOptimizerSession.fromStored(
        id: 'restored',
        mode: AssistantMode.systemPrompt,
        history: [for (final m in live.history) LLMMessage.fromJson(m.toJson())],
      );

      final card = restored.transcript
          .singleWhere((e) => e.kind == OptimizerEntryKind.askUser);
      expect(card.askState, AskUserState.answered);
      expect(card.askAnswers!.single.selected, ['一体袜靴']);
      expect(restored.pendingAskUser, isNull);
    });

    test('a free-text-resolved call restores as dismissed', () {
      final live = newSession();
      live.addUserTurn('go');
      final callId = recordAsk(live);
      PromptOptimizerAgent.resolvePendingAskUserAsFreeText(
        session: live,
        callId: callId,
      );
      final restored = PromptOptimizerSession.fromStored(
        id: 'restored',
        mode: AssistantMode.systemPrompt,
        history: [for (final m in live.history) LLMMessage.fromJson(m.toJson())],
      );

      final card = restored.transcript
          .singleWhere((e) => e.kind == OptimizerEntryKind.askUser);
      expect(card.askState, AskUserState.dismissed);
      expect(card.askAnswers, isNull);
    });

    test('a malformed stored call produces no card at all', () {
      final live = newSession();
      live.addUserTurn('go');
      recordAsk(live, questions: 'not a list');
      final restored = PromptOptimizerSession.fromStored(
        id: 'restored',
        mode: AssistantMode.systemPrompt,
        history: [for (final m in live.history) LLMMessage.fromJson(m.toJson())],
      );

      expect(
        restored.transcript.where((e) => e.kind == OptimizerEntryKind.askUser),
        isEmpty,
      );
    });
  });
}
