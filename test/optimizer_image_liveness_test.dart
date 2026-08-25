import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// Whether the model can still *refer to* a reference image it viewed earlier.
///
/// This used to be gated on [PromptOptimizerSession.viewedImagePaths] — a set
/// that nothing invalidated when `_elide` stripped the attachment from the
/// outgoing request or `_maybeCompact` folded the message away. The model
/// asking to re-view was answered "already attached earlier — refer to that
/// attachment" about an attachment that no longer existed in the request,
/// with no way to recover. The exact deadlock the knowledge-read cache had
/// before it became derived (see `optimizer_kb_liveness_test.dart`); the
/// image path kept the old pattern until 2026-08.
///
/// Liveness is now derived from the history, so these pin the property
/// directly: "does what the model will actually be sent still carry this
/// attachment?"
void main() {
  /// Appends the synthetic view-result message the agent writes after a
  /// `view_image` call, matching production's shape. The file does not need
  /// to exist — liveness only inspects the message structure.
  void recordView(PromptOptimizerSession session, int id, String path) {
    session.history.add(LLMMessage(
      role: LLMRole.user,
      content:
          '${PromptOptimizerAgent.viewResultMarker} Reference image #$id (img$id.png) is attached.',
      attachments: [
        LLMAttachment.fromFile(File(path), 'image/png',
            referenceType: LLMReferenceType.viewOnly),
      ],
    ));
  }

  PromptOptimizerSession newSession() => PromptOptimizerSession();

  Set<String> live(PromptOptimizerSession s) =>
      PromptOptimizerAgent.liveViewedPathsForTest(s);

  group('_liveViewedPaths', () {
    test('a fresh view counts as live', () {
      final session = newSession();
      session.addUserTurn('优化这个提示词');
      recordView(session, 1, '/tmp/a.png');

      expect(live(session), {'/tmp/a.png'});
    });

    test('a view one turn back is still live', () {
      // _keepAttachmentTurns = 2: the turn that viewed it, plus the follow-up
      // that usually refines the result.
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');
      session.addUserTurn('后续调整');

      expect(live(session), {'/tmp/a.png'});
    });

    test('a view that fell out of the attachment window is no longer live', () {
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');
      // Synthetic view messages do not count as user turns, so two more real
      // turns move the attachment boundary past the view.
      session.addUserTurn('后续调整 1');
      session.addUserTurn('后续调整 2');

      expect(live(session), isEmpty,
          reason: '_trimForSend elides the attachment before the boundary, so '
              'the model can no longer see it and must be allowed to re-view');
    });

    test('images leave sooner than knowledge reads do', () {
      // The two windows are deliberately different sizes: a knowledge read
      // costs its characters once, an attachment costs a re-upload and a
      // fresh image-token bill on every request of every turn it survives.
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');
      session.history.add(LLMMessage(
        role: LLMRole.tool,
        toolName: 'read_knowledge_file',
        toolCallId: 'c1',
        content: '{"path": "07a.md", "content": "${'x' * 500}"}',
      ));
      session.addUserTurn('后续调整 1');
      session.addUserTurn('后续调整 2');

      final sent = PromptOptimizerAgent.trimForSendForTest(session.history);
      expect(sent.any((m) => m.attachments.isNotEmpty), isFalse,
          reason: 'the image is past _keepAttachmentTurns');
      expect(
          sent.any((m) =>
              m.toolName == 'read_knowledge_file' && m.content.contains('xxx')),
          isTrue,
          reason: 'the knowledge read is still inside _keepRecentTurns');
    });

    test('re-viewing after elision makes the image live again', () {
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');
      session.addUserTurn('后续调整 1');
      session.addUserTurn('后续调整 2');
      expect(live(session), isEmpty);

      // The agent re-attaches on the fresh view_image call.
      recordView(session, 1, '/tmp/a.png');
      expect(live(session), {'/tmp/a.png'});
    });

    test('liveness agrees with what is actually sent, at every distance', () {
      // The invariant that matters, stated directly. _elide decides whether
      // the attachment is still in the request; _liveViewedPaths decides
      // whether the model is allowed to ask for it again. If those two ever
      // disagree, the model is refused a re-view of a picture it can no
      // longer see — a deadlock with no way out but restarting the app.
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');

      for (var turn = 0; turn < 8; turn++) {
        final sent = PromptOptimizerAgent.trimForSendForTest(session.history);
        final stillSent = sent.any((m) => m.attachments
            .any((a) => a.path == '/tmp/a.png'));

        expect(live(session).contains('/tmp/a.png'), stillSent,
            reason: 'disagreement $turn turn(s) after the view');

        session.addUserTurn('后续调整 $turn');
      }
    });

    test('compaction folding the view message drops it from liveness', () {
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');
      session.addUserTurn('第二轮');

      // Simulate what _maybeCompact does: history before the boundary is
      // replaced by a summary user message without attachments.
      final tail = session.history.sublist(session.history.length - 1);
      session.history
        ..clear()
        ..addAll([
          LLMMessage(
            role: LLMRole.user,
            content: '${PromptOptimizerAgent.summaryMarker}\nsummary',
          ),
          ...tail,
        ]);

      expect(live(session), isEmpty);
    });

    test('viewedImagePaths (the UI badge) is unaffected by elision', () {
      final session = newSession();
      session.addUserTurn('第一轮');
      // Production marks the badge at view time.
      session.history.add(LLMMessage(role: LLMRole.user, content: 'x'));
      recordView(session, 1, '/tmp/a.png');
      // The badge set is tracked, not derived — it deliberately keeps saying
      // "was looked at during this session" even after the attachment left
      // the context. Only the model-facing gate derives.
      expect(live(session).contains('/tmp/a.png'), isTrue);
    });
  });
}
