import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/sub_agent_runner.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

/// A reply cut at the output limit (`finish_reason == 'length'`) runs none
/// of its tool calls, pairs each with a directed `output_truncated` result,
/// and ends the turn after two cuts in a row. Before this the cut call was
/// executed with the empty arguments a half JSON decodes to: a submit_prompt
/// answered "prompt must not be empty", the model redid the whole analysis,
/// and was cut in the same place until the round limit.
void main() {
  usePrivateDataDir('joycai_truncation_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  /// What a cut submit_prompt looks like after the stream accumulator gave
  /// up on its half JSON: the call is there, the arguments decoded to what
  /// survived — here a prompt, to prove it is not staged anyway.
  LLMResponse cutSubmit(int n) => LLMResponse(
        text: '',
        toolCalls: [
          LLMToolCall(id: 'call_$n', name: 'submit_prompt', arguments: const {'prompt': 'half a prompt'}),
        ],
        metadata: const {'finish_reason': 'length', 'completion_tokens': 8192},
      );

  LLMResponse wholeSubmit(int n) => LLMResponse(
        text: '',
        toolCalls: [
          LLMToolCall(id: 'call_$n', name: 'submit_prompt', arguments: const {'prompt': 'the whole prompt'}),
        ],
        metadata: const {'finish_reason': 'tool_calls'},
      );

  test('a cut call is not executed, and its result says why and what to do', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      // cut, the whole delivery, then the model's closing line.
      return switch (requests) {
        1 => cutSubmit(1),
        2 => wholeSubmit(2),
        _ => LLMResponse(text: 'done'),
      };
    };

    await PromptOptimizerAgent.runTurn(session: session, modelIdentifier: 'm', referenceImages: const []);

    // The cut call staged nothing; the retry's whole call did.
    expect(session.promptVersions, 1);
    expect(session.transcript.where((e) => e.kind == OptimizerEntryKind.prompt).single.text, 'the whole prompt');

    // The cut call is paired — the history stays sendable — with the directed result.
    final cutResult = session.history.firstWhere((m) => m.role == LLMRole.tool && m.toolCallId == 'call_1');
    final decoded = jsonDecode(cutResult.content) as Map<String, dynamic>;
    expect(decoded['code'], 'output_truncated');
    expect(decoded['message'], contains('8192 tokens'));
    expect(decoded['message'], contains('ONLY the tool call'));
    expect(PromptOptimizerAgent.repairToolCallPairing(session.history), hasLength(session.history.length));
    expect(session.transcript.any((e) => e.kind == OptimizerEntryKind.error), isFalse);
  });

  test('two cuts in a row end the turn with the truncation stop, not the round limit', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      return cutSubmit(requests);
    };

    await PromptOptimizerAgent.runTurn(session: session, modelIdentifier: 'm', referenceImages: const []);

    expect(requests, maxTruncatedRounds, reason: 'no further rounds are burned on the same cut');
    expect(session.promptVersions, 0);
    expect(session.transcript.last.kind, OptimizerEntryKind.error);
    expect(session.transcript.last.text, PromptOptimizerAgent.truncationStopNoticeToken);
    expect(PromptOptimizerAgent.repairToolCallPairing(session.history), hasLength(session.history.length));
  });

  test('a whole reply between two cuts resets the count', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      // cut, a whole view call, cut, then the delivery.
      return switch (requests) {
        1 => cutSubmit(1),
        2 => LLMResponse(text: '', toolCalls: [
            LLMToolCall(id: 'call_2', name: 'list_reference_images', arguments: const {}),
          ]),
        3 => cutSubmit(3),
        4 => wholeSubmit(4),
        _ => LLMResponse(text: 'done'),
      };
    };

    await PromptOptimizerAgent.runTurn(session: session, modelIdentifier: 'm', referenceImages: const []);

    expect(session.promptVersions, 1);
    expect(session.transcript.any((e) => e.kind == OptimizerEntryKind.error), isFalse);
  });

  test('an empty cut reply — thinking spent the whole cap — counts toward the stop', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    var requests = 0;
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async {
      requests++;
      return LLMResponse(text: '', metadata: const {'finish_reason': 'length'});
    };

    await PromptOptimizerAgent.runTurn(session: session, modelIdentifier: 7, referenceImages: const []);

    expect(requests, maxTruncatedRounds);
    expect(session.transcript.last.kind, OptimizerEntryKind.error);
    expect(session.transcript.last.text, PromptOptimizerAgent.truncationStopNoticeToken);
    expect(session.transcript.last.modelDbId, 7, reason: 'the card jumps to the model that produced the reply');
  });

  test('a cut plain-text reply is kept as a reply and marked truncated', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async => LLMResponse(
          text: 'I would suggest a low-angle shot with',
          metadata: const {'finish_reason': 'length'},
        );

    await PromptOptimizerAgent.runTurn(session: session, modelIdentifier: 'm', referenceImages: const []);

    final reply = session.transcript.last;
    expect(reply.kind, OptimizerEntryKind.assistant);
    expect(reply.truncated, isTrue);
    expect(session.history.last.role, LLMRole.assistant);
  });

  test('the mark and the model survive a restart', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    PromptOptimizerAgent.debugRequestOverride = (messages, tools, options) async => LLMResponse(
          text: 'I would suggest a low-angle shot with',
          metadata: const {'finish_reason': 'length'},
        );

    await PromptOptimizerAgent.runTurn(session: session, modelIdentifier: 7, referenceImages: const []);

    // What the repository stores and reads back.
    final stored = [
      for (final m in session.history) LLMMessage.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map<String, dynamic>),
    ];
    final restored = PromptOptimizerSession.fromStored(
      id: session.id,
      mode: session.mode,
      history: stored,
    );
    final reply = restored.transcript.lastWhere((e) => e.kind == OptimizerEntryKind.assistant);
    expect(reply.truncated, isTrue);
    expect(reply.modelDbId, 7);
  });

  test('host bookkeeping stays off a row that has none', () {
    final json = LLMMessage(role: LLMRole.assistant, content: 'done').toJson();
    expect(json.containsKey('truncated'), isFalse);
    expect(json.containsKey('modelDbId'), isFalse);
    final old = LLMMessage.fromJson(const {'role': 'assistant', 'content': 'done'});
    expect(old.truncated, isFalse);
    expect(old.modelDbId, isNull);
  });

  test('a whole plain-text reply is not marked', () async {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    PromptOptimizerAgent.debugRequestOverride =
        (messages, tools, options) async => LLMResponse(text: 'done', metadata: const {'finish_reason': 'stop'});

    await PromptOptimizerAgent.runTurn(session: session, modelIdentifier: 'm', referenceImages: const []);

    expect(session.transcript.last.truncated, isFalse);
  });

  group('the sub-agent applies the same rule', () {
    final tools = [
      LLMTool(name: 'read_knowledge_file', description: '', parameters: const {'type': 'object'}),
    ];

    test('a cut call is not run and the retry proceeds', () async {
      var requests = 0;
      var executed = 0;
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'task',
        tools: tools,
        executeTool: (call, occupied) {
          executed++;
          return const {'status': 'ok'};
        },
        request: (messages, tools) async {
          requests++;
          return switch (requests) {
            1 => LLMResponse(
                text: '',
                toolCalls: [LLMToolCall(id: 'c1', name: 'read_knowledge_file', arguments: const {})],
                metadata: const {'finish_reason': 'length'},
              ),
            _ => LLMResponse(text: 'findings'),
          };
        },
      );

      expect(executed, 0);
      expect(result.output, 'findings');
      expect(result.cancelled, isFalse);
    });

    test('two cuts in a row end the run with no deliverable', () async {
      var requests = 0;
      var executed = 0;
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'task',
        tools: tools,
        executeTool: (call, occupied) {
          executed++;
          return const {'status': 'ok'};
        },
        request: (messages, tools) async {
          requests++;
          return LLMResponse(
            text: '',
            toolCalls: [LLMToolCall(id: 'c$requests', name: 'read_knowledge_file', arguments: const {})],
            metadata: const {'finish_reason': 'length'},
          );
        },
      );

      expect(requests, maxTruncatedRounds);
      expect(executed, 0);
      expect(result.output, isEmpty);
      expect(result.cancelled, isFalse);
    });
  });
}
