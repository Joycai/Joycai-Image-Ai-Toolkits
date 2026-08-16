import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/sub_agent_runner.dart';

/// Pins the sub-agent loop's invariants (pairing, cancellation stubs, the
/// force-text last round) and the delegate routing/template rules from
/// docs/plans/2026-08-ai-improvement-plan.md §3.
void main() {
  LLMToolCall toolCall(String id, [String name = 'read_knowledge_file']) =>
      LLMToolCall(id: id, name: name, arguments: {'path': 'x.md'});

  group('SubAgentRunner', () {
    test('a plain-text first reply is the deliverable', () async {
      var executed = 0;
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        executeTool: (_, _) {
          executed++;
          return {};
        },
        request: (messages, tools) async {
          expect(messages.first.role, LLMRole.system);
          expect(messages[1].content, 'brief');
          return LLMResponse(text: 'findings');
        },
      );
      expect(result.output, 'findings');
      expect(result.cancelled, isFalse);
      expect(result.turnsUsed, 1);
      expect(executed, 0);
    });

    test('every tool call gets a paired result before the next request',
        () async {
      List<LLMMessage>? secondRequestMessages;
      var turn = 0;
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        executeTool: (call, _) => {'ok': call.id},
        request: (messages, tools) async {
          turn++;
          if (turn == 1) {
            return LLMResponse(
                text: '', toolCalls: [toolCall('a'), toolCall('b')]);
          }
          secondRequestMessages = List.of(messages);
          return LLMResponse(text: 'done');
        },
      );
      expect(result.output, 'done');
      // sys + task + assistant echo + two paired results.
      final msgs = secondRequestMessages!;
      expect(msgs, hasLength(5));
      expect(msgs[2].toolCalls, hasLength(2));
      expect(msgs[3].toolCallId, 'a');
      expect(msgs[4].toolCallId, 'b');
      expect(jsonDecode(msgs[3].content), {'ok': 'a'});
    });

    test('a throwing executor becomes an error result, not an escape',
        () async {
      var turn = 0;
      List<LLMMessage>? secondRequestMessages;
      await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        executeTool: (call, _) =>
            call.id == 'a' ? throw StateError('boom') : {'ok': call.id},
        request: (messages, tools) async {
          turn++;
          if (turn == 1) {
            return LLMResponse(
                text: '', toolCalls: [toolCall('a'), toolCall('b')]);
          }
          secondRequestMessages = List.of(messages);
          return LLMResponse(text: 'done');
        },
      );
      final results = secondRequestMessages!.sublist(3);
      expect(jsonDecode(results[0].content)['status'], 'error');
      expect(jsonDecode(results[1].content), {'ok': 'b'});
    });

    test('cancellation mid-batch stubs the remaining calls, then stops',
        () async {
      var cancelled = false;
      final executedIds = <String>[];
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        isCancelled: () => cancelled,
        executeTool: (call, _) {
          executedIds.add(call.id);
          cancelled = true; // The user stops the task during the first tool.
          return {'ok': call.id};
        },
        request: (messages, tools) async {
          return LLMResponse(
              text: '', toolCalls: [toolCall('a'), toolCall('b')]);
        },
      );
      expect(result.cancelled, isTrue);
      expect(executedIds, ['a']);
    });

    test('the last turn withholds tools — force-text', () async {
      final toolsPerTurn = <List<LLMTool>?>[];
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: [LLMTool(name: 't', description: 'd', parameters: {})],
        maxTurns: 2,
        executeTool: (_, _) => {'ok': true},
        request: (messages, tools) async {
          toolsPerTurn.add(tools);
          if (toolsPerTurn.length == 1) {
            return LLMResponse(text: '', toolCalls: [toolCall('a')]);
          }
          return LLMResponse(text: 'wrapped up');
        },
      );
      expect(toolsPerTurn, hasLength(2));
      expect(toolsPerTurn[0], isNotNull);
      expect(toolsPerTurn[1], isNull);
      expect(result.output, 'wrapped up');
      expect(result.turnsUsed, 2);
    });

    test('occupancy is recomputed per call, not per turn', () async {
      // A batch of reads must converge on the remaining window: the first
      // call's result is already paired (and counted) before the second
      // call's budget is computed — each claiming the same free window is
      // exactly the over-grant the main loop's read cap forbids.
      final occupiedSeen = <int>[];
      var turn = 0;
      await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        executeTool: (call, occupied) {
          occupiedSeen.add(occupied);
          return {'bulk': 'x' * 5000};
        },
        request: (messages, tools) async {
          turn++;
          if (turn == 1) {
            return LLMResponse(
                text: '', toolCalls: [toolCall('a'), toolCall('b')]);
          }
          return LLMResponse(text: 'done');
        },
      );
      expect(occupiedSeen, hasLength(2));
      // The second call sees the first call's ~5000-char result.
      expect(occupiedSeen[1], greaterThan(occupiedSeen[0] + 4000));
    });

    test('an empty run reports empty output for the caller to reject',
        () async {
      final result = await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        tools: const [],
        executeTool: (_, _) => {},
        request: (messages, tools) async => LLMResponse(text: '   '),
      );
      expect(result.output, isEmpty);
    });
  });

  group('delegate task template (two shapes, playbook 09 §refs)', () {
    test('without paths there is no "start from" section at all', () {
      final msg = PromptOptimizerAgent.buildDelegateTask('the brief', const []);
      expect(msg, 'the brief');
      expect(msg, isNot(contains('Start from')));
    });

    test('with paths the section lists them verbatim', () {
      final msg = PromptOptimizerAgent.buildDelegateTask(
          'the brief', const ['a.md', 'rules/b.md']);
      expect(msg, contains('Start from these knowledge-base files:'));
      expect(msg, contains('- a.md'));
      expect(msg, contains('- rules/b.md'));
    });
  });

  group('toolsetFor routing', () {
    Iterable<String> names(List<LLMTool> tools) => tools.map((t) => t.name);

    test('delegate and read_note appear iff any kind is available', () {
      expect(
        names(PromptOptimizerAgent.toolsetFor(
          acceptsImageInput: true,
          knowledgeMode: true,
          editMode: false,
          delegateKinds: const {'knowledge'},
        )),
        containsAll(['delegate', 'read_note']),
      );
      // No available kind: neither tool exists.
      final none = names(PromptOptimizerAgent.toolsetFor(
        acceptsImageInput: true,
        knowledgeMode: true,
        editMode: false,
      ));
      expect(none, isNot(contains('delegate')));
      expect(none, isNot(contains('read_note')));
    });

    test('draft kind works outside knowledge sessions', () {
      // A system-prompt session with reference images and an image-capable
      // sub-agent model still gets drafting delegation.
      final tools = names(PromptOptimizerAgent.toolsetFor(
        acceptsImageInput: true,
        knowledgeMode: false,
        editMode: false,
        delegateKinds: const {'draft'},
      ));
      expect(tools, contains('delegate'));
      expect(tools, isNot(contains('read_knowledge_file')));
    });

    test('delegate is additive — the direct read tool stays', () {
      final tools = names(PromptOptimizerAgent.toolsetFor(
        acceptsImageInput: true,
        knowledgeMode: true,
        editMode: false,
        delegateKinds: const {'knowledge'},
      ));
      expect(tools, contains('read_knowledge_file'));
      expect(tools, contains('delegate'));
    });

    test('context exhaustion removes reads but keeps delegate', () {
      // The sub-agent researches in its own fresh context — running out of
      // room in the main one is exactly when delegation is most useful.
      final tools = names(PromptOptimizerAgent.toolsetFor(
        acceptsImageInput: true,
        knowledgeMode: true,
        editMode: false,
        delegateKinds: const {'knowledge'},
        contextExhausted: true,
      ));
      expect(tools, isNot(contains('read_knowledge_file')));
      expect(tools, contains('delegate'));
    });

    test('edit mode keeps the write tool; text-only drops image tools', () {
      final tools = names(PromptOptimizerAgent.toolsetFor(
        acceptsImageInput: false,
        knowledgeMode: true,
        editMode: true,
        delegateKinds: const {'knowledge'},
      ));
      expect(tools, contains('write_knowledge_file'));
      expect(tools, contains('delegate'));
      expect(tools, isNot(contains('view_image')));
      expect(tools, isNot(contains('list_reference_images')));
    });
  });

  group('delegateToolFor schema shaping', () {
    Map<String, dynamic> props(LLMTool t) =>
        (t.parameters['properties'] as Map).cast<String, dynamic>();

    test('the kind enum lists exactly the available kinds', () {
      final both =
          PromptOptimizerAgent.delegateToolFor(const {'knowledge', 'draft'});
      expect((props(both)['kind'] as Map)['enum'], ['draft', 'knowledge']);

      final only = PromptOptimizerAgent.delegateToolFor(const {'knowledge'});
      expect((props(only)['kind'] as Map)['enum'], ['knowledge']);
    });

    test("each kind's private field appears only with its kind", () {
      // A field describing an unavailable capability reads as an
      // instruction to try it.
      final knowledge =
          PromptOptimizerAgent.delegateToolFor(const {'knowledge'});
      expect(props(knowledge), contains('paths'));
      expect(props(knowledge), isNot(contains('image_id')));

      final draft = PromptOptimizerAgent.delegateToolFor(const {'draft'});
      expect(props(draft), contains('image_id'));
      expect(props(draft), isNot(contains('paths')));
      expect(draft.description, contains('image_id'));
      expect(draft.description, isNot(contains('read_knowledge_file')));
    });
  });

  group('runner attachments', () {
    test('attachments ride on the task message only', () async {
      List<LLMMessage>? seen;
      await SubAgentRunner.run(
        modelIdentifier: 'm',
        systemPrompt: 'sys',
        task: 'brief',
        attachments: [
          LLMAttachment.fromBytes(Uint8List.fromList([1, 2, 3]), 'image/png'),
        ],
        tools: const [],
        executeTool: (_, _) => {},
        request: (messages, tools) async {
          seen = List.of(messages);
          return LLMResponse(text: 'done');
        },
      );
      expect(seen![0].attachments, isEmpty);
      expect(seen![1].attachments, hasLength(1));
    });
  });
}
