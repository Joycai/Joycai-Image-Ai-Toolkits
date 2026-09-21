import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';

/// Standard 07 §3.6: a request carries at most the newest few image
/// attachments, however many sit inside the attachment window.
///
/// The window alone is measured in turns (`_keepAttachmentTurns`), and one
/// turn can view every reference image — each then re-uploaded on every
/// later request of that turn. The cap and the re-view gate are two halves
/// of one rule, like the window itself: an image the cap drops must be
/// viewable again (`optimizer_image_liveness_test.dart`, invariant 4).
void main() {
  String pathOf(int id) => '/tmp/cap_img$id.png';

  /// The synthetic view-result message the agent writes after a view_image
  /// call. The file need not exist — nothing here reads it.
  void recordView(PromptOptimizerSession session, int id) {
    session.history.add(LLMMessage(
      role: LLMRole.user,
      content:
          '${PromptOptimizerAgent.viewResultMarker} Reference image #$id (img$id.png) is attached.',
      attachments: [
        LLMAttachment.fromFile(File(pathOf(id)), 'image/png',
            referenceType: LLMReferenceType.viewOnly),
      ],
    ));
  }

  List<String> sent(PromptOptimizerSession session) => [
        for (final m in PromptOptimizerAgent.trimForSendForTest(session.history))
          for (final a in m.attachments)
            if (a.path != null) a.path!,
      ];

  Set<String> live(PromptOptimizerSession session) =>
      PromptOptimizerAgent.liveViewedPathsForTest(session);

  test('one turn viewing five images sends only the newest three', () {
    final session = PromptOptimizerSession();
    session.addUserTurn('看这些参考图');
    for (var id = 1; id <= 5; id++) {
      recordView(session, id);
    }

    expect(sent(session), [pathOf(3), pathOf(4), pathOf(5)]);
    expect(live(session), {pathOf(3), pathOf(4), pathOf(5)});
  });

  test('the cap counts across turns inside the attachment window', () {
    final session = PromptOptimizerSession();
    session.addUserTurn('第一轮');
    recordView(session, 1);
    recordView(session, 2);
    session.addUserTurn('第二轮');
    recordView(session, 3);
    recordView(session, 4);

    expect(sent(session), [pathOf(2), pathOf(3), pathOf(4)]);
    expect(live(session), {pathOf(2), pathOf(3), pathOf(4)});
  });

  test('an image the cap dropped can be viewed again, and is then live', () {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    for (var id = 1; id <= 4; id++) {
      recordView(session, id);
    }
    expect(live(session), isNot(contains(pathOf(1))));

    recordView(session, 1);
    expect(sent(session), [pathOf(3), pathOf(4), pathOf(1)]);
    expect(live(session), {pathOf(3), pathOf(4), pathOf(1)});
  });

  test('liveness agrees with what is sent, at every image count', () {
    final session = PromptOptimizerSession();
    session.addUserTurn('go');
    for (var id = 1; id <= 7; id++) {
      recordView(session, id);
      expect(live(session), sent(session).toSet(), reason: 'after $id view(s)');
    }
  });

  group('with force-view-all-images', () {
    // The per-model flag promises the model has seen every reference before
    // submit_prompt, so the current turn keeps all of its attachments; the
    // cap still applies to older rounds.
    List<String> sentForced(PromptOptimizerSession session) => [
          for (final m in PromptOptimizerAgent.trimForSendForTest(session.history,
              keepCurrentTurnImages: true))
            for (final a in m.attachments)
              if (a.path != null) a.path!,
        ];

    Set<String> liveForced(PromptOptimizerSession session) =>
        PromptOptimizerAgent.liveViewedPathsForTest(session, keepCurrentTurnImages: true);

    test('the current turn keeps every image; older rounds are capped', () {
      final session = PromptOptimizerSession();
      session.addUserTurn('第一轮');
      for (var id = 1; id <= 3; id++) {
        recordView(session, id);
      }
      session.addUserTurn('看完所有参考图再写');
      for (var id = 4; id <= 8; id++) {
        recordView(session, id);
      }

      expect(sentForced(session), [for (var id = 4; id <= 8; id++) pathOf(id)]);
      expect(liveForced(session), {for (var id = 4; id <= 8; id++) pathOf(id)});
    });

    test('liveness agrees with what is sent, at every image count', () {
      final session = PromptOptimizerSession();
      session.addUserTurn('第一轮');
      recordView(session, 1);
      recordView(session, 2);
      session.addUserTurn('第二轮');
      for (var id = 3; id <= 9; id++) {
        recordView(session, id);
        expect(liveForced(session), sentForced(session).toSet(), reason: 'after view $id');
      }
    });
  });
}
