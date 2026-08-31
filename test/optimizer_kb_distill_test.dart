import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/assistant_kb_distill.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// The knowledge-base optimization loop, model-free: the feedback-message
/// wire format, the derived pending-distill / write-escalation state, and the
/// iteration ledger the distill request embeds.
void main() {
  PromptOptimizerSession kbSession() =>
      PromptOptimizerSession(mode: AssistantMode.knowledgeBase);

  /// Appends the assistant message + paired tool result of one submit_prompt,
  /// matching production's shape.
  void recordSubmit(PromptOptimizerSession session, String prompt, {String? note}) {
    final callId = 'call_${session.history.length}';
    session.history.add(LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [
        LLMToolCall(
          id: callId,
          name: 'submit_prompt',
          arguments: {'prompt': prompt, 'note': ?note},
        ),
      ],
    ));
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: '{"status":"ok"}',
      toolCallId: callId,
      toolName: 'submit_prompt',
    ));
  }

  group('result feedback wire format', () {
    test('addResultFeedback round-trips through tryParseResultFeedback', () {
      final session = kbSession();
      session.addUserTurn('画一个角色');
      session.addResultFeedback(
        imageName: 'gen_42.png',
        promptVersion: 3,
        feedback: '手部畸形，光线太平',
      );

      final msg = session.history.last;
      expect(msg.role, LLMRole.user);
      expect(msg.content, startsWith(PromptOptimizerAgent.resultFeedbackMarker));
      expect(msg.attachments, isEmpty, reason: 'the image is viewed lazily, never attached here');

      final parsed = PromptOptimizerAgent.tryParseResultFeedback(msg.content);
      expect(parsed, isNotNull);
      expect(parsed!.promptVersion, 3);
      expect(parsed.imageName, 'gen_42.png');
      expect(parsed.feedback, '手部畸形，光线太平');

      final entry = session.transcript.last;
      expect(entry.kind, OptimizerEntryKind.resultFeedback);
      expect(entry.version, 3);
      expect(entry.note, 'gen_42.png');
      expect(entry.text, '手部畸形，光线太平');
    });

    test('a non-marker or malformed-header message parses to null', () {
      expect(PromptOptimizerAgent.tryParseResultFeedback('plain text'), isNull);
      expect(
        PromptOptimizerAgent.tryParseResultFeedback(
            '${PromptOptimizerAgent.resultFeedbackMarker} not json\nfeedback'),
        isNull,
      );
      expect(
        PromptOptimizerAgent.tryParseResultFeedback(
            '${PromptOptimizerAgent.resultFeedbackMarker} {"prompt_version":1}\nno image key'),
        isNull,
      );
    });

    test('resultImageInfoByName derives from history, latest feedback wins', () {
      final session = kbSession();
      session.addUserTurn('go');
      session.addResultFeedback(imageName: 'a.png', promptVersion: 1, feedback: 'first');
      session.addResultFeedback(imageName: 'a.png', promptVersion: 2, feedback: 'second');
      session.addResultFeedback(imageName: 'b.png', promptVersion: 2, feedback: 'other');

      final info = PromptOptimizerAgent.resultImageInfoByName(session.history);
      expect(info.keys, containsAll(['a.png', 'b.png']));
      expect(info['a.png']!.promptVersion, 2);
      expect(info['a.png']!.feedback, 'second');
      expect(info['b.png']!.feedback, 'other');
    });

    test('fromStored rebuilds feedback and distill entries from markers', () {
      final live = kbSession();
      live.addUserTurn('优化');
      live.addResultFeedback(imageName: 'r.png', promptVersion: 1, feedback: '构图太空');
      live.addKbDistillTurn(
          '${PromptOptimizerAgent.kbDistillMarker} distill request body');

      final restored = PromptOptimizerSession.fromStored(
        id: live.id,
        mode: AssistantMode.knowledgeBase,
        history: List.of(live.history),
      );

      final kinds = restored.transcript.map((e) => e.kind).toList();
      expect(
        kinds,
        containsAllInOrder([
          OptimizerEntryKind.user,
          OptimizerEntryKind.resultFeedback,
          OptimizerEntryKind.kbDistill,
        ]),
      );
      final feedback = restored.transcript
          .firstWhere((e) => e.kind == OptimizerEntryKind.resultFeedback);
      expect(feedback.version, 1);
      expect(feedback.note, 'r.png');
      expect(feedback.text, '构图太空');
    });
  });

  group('pending distill and write escalation', () {
    test('hasPendingKbDistill follows the latest real user turn', () {
      final session = kbSession();
      expect(session.hasPendingKbDistill, isFalse);

      session.addUserTurn('优化');
      expect(session.hasPendingKbDistill, isFalse);

      session.addKbDistillTurn('${PromptOptimizerAgent.kbDistillMarker} go');
      expect(session.hasPendingKbDistill, isTrue);

      // Synthetic user-role messages (view attachments, summaries) must not
      // clear it — the distill turn itself appends them.
      session.history.add(LLMMessage(
        role: LLMRole.user,
        content: '${PromptOptimizerAgent.viewResultMarker} Reference image #1 (x) is attached.',
      ));
      expect(session.hasPendingKbDistill, isTrue);

      // The user's next ordinary message does clear it.
      session.addUserTurn('继续调整');
      expect(session.hasPendingKbDistill, isFalse);
    });

    test('a free-text answer to the distill turn\'s ask_user keeps it pending',
        () {
      final session = kbSession();
      session.addKbDistillTurn('${PromptOptimizerAgent.kbDistillMarker} go');
      expect(session.hasPendingKbDistill, isTrue);

      // The distill turn pauses on an ask_user (rule 4: contradictions); the
      // model's message carries the call and the turn returns with it dangling.
      session.history.add(LLMMessage(
        role: LLMRole.assistant,
        content: '',
        toolCalls: [
          LLMToolCall(id: 'ask1', name: 'ask_user', arguments: const {}),
        ],
      ));
      // The user answers in the composer, not the card: the call is paired
      // with a tool result, then the free text is appended as a user turn —
      // a real user turn, but one immediately preceded by that tool result.
      session.history.add(LLMMessage(
        role: LLMRole.tool,
        content: '{"status":"ok"}',
        toolCallId: 'ask1',
        toolName: 'ask_user',
      ));
      session.addUserTurn('用新规则，把旧的降级为例外');

      // It continues the distill turn, so write access must survive it —
      // exactly as the card path (a bare tool result) already does.
      expect(session.hasPendingKbDistill, isTrue);
    });

    test('a pending distill escalates canWriteKnowledge in knowledgeBase mode, policy permitting', () {
      final session = kbSession();
      session.addUserTurn('优化');
      expect(session.canWriteKnowledge, isFalse);

      session.addKbDistillTurn('${PromptOptimizerAgent.kbDistillMarker} go');
      expect(session.canWriteKnowledge, isTrue);

      session.writePolicy = const KbWritePolicy(allowWrites: false);
      expect(session.canWriteKnowledge, isFalse,
          reason: 'the write switch still outranks the escalation');
    });

    test('knowledgeEdit mode keeps its unconditional write access', () {
      final session = PromptOptimizerSession(mode: AssistantMode.knowledgeEdit);
      expect(session.canWriteKnowledge, isTrue);
    });
  });

  group('iteration ledger', () {
    test('versions in order, feedback bound positionally', () {
      final session = kbSession();
      session.addUserTurn('画一个角色');
      recordSubmit(session, 'prompt one', note: 'first pass');
      session.addResultFeedback(imageName: 'a.png', promptVersion: 1, feedback: '手崩了');
      recordSubmit(session, 'prompt two', note: 'fixed hands');
      session.addResultFeedback(imageName: 'b.png', promptVersion: 2, feedback: '风格跑了');

      final ledger = AssistantKbDistill.buildIterationLedger(session.history);
      expect(ledger, hasLength(2));
      expect(ledger[0].version, 1);
      expect(ledger[0].note, 'first pass');
      expect(ledger[0].feedback.single.feedback, '手崩了');
      expect(ledger[1].version, 2);
      expect(ledger[1].feedback.single.imageName, 'b.png');
    });

    test('duplicate rows from compaction tail copies collapse', () {
      final session = kbSession();
      session.addUserTurn('go');
      recordSubmit(session, 'prompt one');
      session.addResultFeedback(imageName: 'a.png', promptVersion: 1, feedback: 'bad');
      // What loadFullHistory yields after compactAll re-appended the tail:
      // the same messages appear again after the flagged originals.
      final duplicated = [...session.history, ...session.history];

      final ledger = AssistantKbDistill.buildIterationLedger(duplicated);
      expect(ledger, hasLength(1));
      expect(ledger.single.feedback, hasLength(1));
    });

    test('feedback before any version, and empty submits, are ignored', () {
      final session = kbSession();
      session.addUserTurn('go');
      session.addResultFeedback(imageName: 'a.png', promptVersion: 1, feedback: 'orphan');
      recordSubmit(session, '   ');

      expect(AssistantKbDistill.buildIterationLedger(session.history), isEmpty);
    });

    test('render marks the final version and excerpts long prompts', () {
      final session = kbSession();
      session.addUserTurn('go');
      recordSubmit(session, 'p' * 2000);
      recordSubmit(session, 'q' * 2000, note: 'final tweak');
      session.addResultFeedback(imageName: 'a.png', promptVersion: 2, feedback: '满意');

      final rendered = AssistantKbDistill.renderIterationLedger(
          AssistantKbDistill.buildIterationLedger(session.history));
      expect(rendered, contains('v1'));
      expect(rendered, contains('v2 (final) — final tweak'));
      expect(rendered, contains('user feedback (image a.png): 满意'));
      expect(rendered, isNot(contains('p' * 500)),
          reason: 'earlier prompts are excerpted, not embedded whole');
      expect(rendered, contains('…'));
    });
  });

  group('stageKbDistillRequest', () {
    test('stages the marker turn when there is something to distill', () async {
      final session = kbSession();
      session.addUserTurn('优化');
      recordSubmit(session, 'prompt one');
      session.addResultFeedback(imageName: 'a.png', promptVersion: 1, feedback: 'ok');

      final result =
          await AssistantKbDistill.stageKbDistillRequest(session: session);
      expect(result, KbDistillStageResult.staged);
      expect(session.history.last.role, LLMRole.user);
      expect(session.history.last.content,
          startsWith(PromptOptimizerAgent.kbDistillMarker));
      expect(session.history.last.content, contains('v1'));
      expect(session.hasPendingKbDistill, isTrue);
      expect(session.transcript.last.kind, OptimizerEntryKind.kbDistill);
    });

    test('refuses when nothing was ever submitted', () async {
      final session = kbSession();
      session.addUserTurn('优化');
      expect(await AssistantKbDistill.stageKbDistillRequest(session: session),
          KbDistillStageResult.nothingToDistill);
    });

    test('refuses a second click while the first request has not run', () async {
      final session = kbSession();
      session.addUserTurn('优化');
      recordSubmit(session, 'prompt one');
      await AssistantKbDistill.stageKbDistillRequest(session: session);

      expect(await AssistantKbDistill.stageKbDistillRequest(session: session),
          KbDistillStageResult.alreadyPending);
    });

    test('refuses outside knowledge sessions', () async {
      final session = PromptOptimizerSession(mode: AssistantMode.systemPrompt);
      expect(await AssistantKbDistill.stageKbDistillRequest(session: session),
          KbDistillStageResult.notKnowledgeSession);
    });
  });
}
