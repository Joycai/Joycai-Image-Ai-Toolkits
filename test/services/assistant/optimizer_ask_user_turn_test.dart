import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

void main() {
  sqfliteFfiInit();
  late DatabaseService db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() async {
    PromptOptimizerAgent.debugRequestOverride = null;
    await closeTestDatabase(db);
  });

  const questions = [
    {
      'header': 'Scene',
      'question': 'Where should the subject be?',
      'options': [
        {'label': 'Studio'},
        {'label': 'Garden'},
      ],
    },
  ];
  LLMToolCall ask(String id) =>
      LLMToolCall(id: id, name: 'ask_user', arguments: const {'questions': questions});

  Future<void> run(PromptOptimizerSession session) => PromptOptimizerAgent.runTurn(
    session: session,
    modelIdentifier: 'test-model',
    referenceImages: const [],
    knowledgeRoot: '.',
    knowledgeEntryContent: 'Ask for a scene before writing a prompt.',
    database: db,
  );

  for (final askFirst in [true, false]) {
    test('batched question takes priority with ask first = $askFirst', () async {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase);
      session.addUserTurn('Make a portrait');
      final otherCalls = [
        LLMToolCall(id: 'view', name: 'view_image', arguments: const {'id': 1}),
        LLMToolCall(id: 'submit', name: 'submit_prompt', arguments: const {'prompt': 'premature'}),
        ask('second-question'),
      ];
      var requests = 0;
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
        requests++;
        return LLMResponse(
          text: '',
          toolCalls: [
            if (askFirst) ask('question'),
            ...otherCalls.take(2),
            if (!askFirst) ask('question'),
            otherCalls.last,
          ],
        );
      };
      await run(session);

      expect(requests, 1, reason: 'Showing a valid card requires no model retry');
      expect(session.pendingAskUser?.callId, 'question');
      expect(session.refinedPrompt, isNull);
      expect(session.history.where((m) => m.attachments.isNotEmpty), isEmpty);
      expect(session.transcript.where((e) => e.kind == OptimizerEntryKind.askUser), hasLength(1));
      final results = session.history.where((m) => m.role == LLMRole.tool).toList();
      expect(results.map((m) => m.toolCallId), ['view', 'submit', 'second-question']);
      for (final result in results) {
        expect(jsonDecode(result.content)['status'], 'deferred');
      }
      expect(PromptOptimizerAgent.repairToolCallPairing(session.history), session.history);
      expect(PromptOptimizerAgent.lastBatchSubmittedPromptForTest(session.history), isFalse);

      final restored = PromptOptimizerSession.fromStored(
        id: session.id,
        history: List.of(session.history),
        mode: AssistantMode.knowledgeBase,
      );
      expect(restored.pendingAskUser?.callId, 'question');
      expect(restored.refinedPrompt, isNull);
      expect(restored.promptVersions, 0);
      expect(restored.transcript.where((e) => e.kind == OptimizerEntryKind.prompt), isEmpty);
      expect(restored.transcript.where((e) => e.kind == OptimizerEntryKind.askUser), hasLength(1));
      PromptOptimizerAgent.answerAskUser(
        session: restored,
        callId: 'question',
        answers: const [
          AskUserAnswer(header: 'Scene', selected: ['Garden']),
        ],
      );
      var resumedRequests = 0;
      PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
        if (++resumedRequests > 1) return LLMResponse(text: 'Done');
        final assistantIndex = messages.indexWhere((m) => m.toolCalls.isNotEmpty);
        final paired = messages.skip(assistantIndex + 1).take(4).toList();
        expect(paired.every((m) => m.role == LLMRole.tool), isTrue);
        expect(paired.map((m) => m.toolCallId).toSet(), {
          'view',
          'submit',
          'second-question',
          'question',
        });
        expect(jsonDecode(paired.last.content)['answers'][0]['selected'], ['Garden']);
        return LLMResponse(
          text: '',
          toolCalls: [
            LLMToolCall(
              id: 'garden-prompt',
              name: 'submit_prompt',
              arguments: const {'prompt': 'A portrait in a garden'},
            ),
          ],
        );
      };
      await run(restored);
      expect(restored.pendingAskUser, isNull);
      expect(restored.refinedPrompt, 'A portrait in a garden');
    });
  }

  test('invalid question does not prevent ordinary tools from running', () async {
    final session = PromptOptimizerSession(mode: AssistantMode.knowledgeBase);
    session.addUserTurn('Make a portrait in a garden');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      if (++requests > 1) return LLMResponse(text: 'Done');
      return LLMResponse(
        text: '',
        toolCalls: [
          LLMToolCall(id: 'bad', name: 'ask_user', arguments: const {'questions': []}),
          LLMToolCall(id: 'submit', name: 'submit_prompt', arguments: const {'prompt': 'portrait'}),
        ],
      );
    };
    await run(session);
    expect(session.pendingAskUser, isNull);
    expect(session.refinedPrompt, 'portrait');
  });

  test('compaction does not promote a deferred prompt into a delivery', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('First turn');
    session.history.addAll([
      LLMMessage(
        role: LLMRole.assistant,
        content: '',
        toolCalls: [
          LLMToolCall(
            id: 'deferred',
            name: 'submit_prompt',
            arguments: const {'prompt': 'premature'},
          ),
        ],
      ),
      LLMMessage(
        role: LLMRole.tool,
        content: jsonEncode({'status': 'deferred'}),
        toolCallId: 'deferred',
        toolName: 'submit_prompt',
      ),
    ]);
    for (var i = 0; i < 8; i++) {
      session.addUserTurn('Turn $i');
      session.history.add(LLMMessage(role: LLMRole.assistant, content: 'x' * 600));
    }
    session.addUserTurn('Continue');
    var summaries = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      if (messages.first.content.startsWith('You compress')) {
        summaries++;
        expect(messages.last.content, isNot(contains('SUBMITTED PROMPT:')));
        return LLMResponse(text: 'The user still needs a prompt.');
      }
      return LLMResponse(text: 'Ready');
    };
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: 'test-model',
      referenceImages: const [],
      contextWindow: 2000,
      database: db,
    );
    expect(summaries, 1);
    expect(session.history.first.content, isNot(contains(PromptOptimizerAgent.latestPromptMarker)));
    expect(session.refinedPrompt, isNull);
  });
}
