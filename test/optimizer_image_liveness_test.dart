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

    test('a view that fell out of the recent window is no longer live', () {
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');
      // Push the view past the protected window (_keepRecentTurns = 6 real
      // user turns). Synthetic view messages do not count as user turns, so
      // six more real turns move the boundary beyond the view.
      for (int i = 0; i < 6; i++) {
        session.addUserTurn('后续调整 $i');
      }

      expect(live(session), isEmpty,
          reason: '_trimForSend elides the attachment before the boundary, so '
              'the model can no longer see it and must be allowed to re-view');
    });

    test('re-viewing after elision makes the image live again', () {
      final session = newSession();
      session.addUserTurn('第一轮');
      recordView(session, 1, '/tmp/a.png');
      for (int i = 0; i < 6; i++) {
        session.addUserTurn('后续调整 $i');
      }
      expect(live(session), isEmpty);

      // The agent re-attaches on the fresh view_image call.
      recordView(session, 1, '/tmp/a.png');
      expect(live(session), {'/tmp/a.png'});
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
