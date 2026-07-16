import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// Whether the model can still *read* a knowledge page it was given earlier.
///
/// This used to be tracked in a `Set<String>` of `'path#page'` keys that nobody
/// invalidated when the content it pointed at was removed. `_elide` swaps a
/// read's result for a stub once it falls out of the recent window, and
/// `_maybeCompact` folds it into a summary that drops tool results outright —
/// but the key survived both, so the model asking to re-read was answered
/// "already in the conversation — refer to the earlier result" pointing at
/// content that no longer existed. It had no way to recover, and restarting the
/// app fixed it (restore rebuilt the cache from the surviving rows), which is
/// exactly why it was hard to reproduce.
///
/// Liveness is now derived from the history itself, so these pin the property
/// directly: "does what the model will actually be sent still contain this?"
void main() {
  /// Appends the assistant call + tool result pair the agent writes for one
  /// `read_knowledge_file`, matching production's shape.
  void recordRead(PromptOptimizerSession session, String path, int page,
      {String content = 'rule body'}) {
    final callId = 'call_${session.history.length}';
    session.history.add(LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [
        LLMToolCall(
          id: callId,
          name: 'read_knowledge_file',
          arguments: {'path': path, 'page': page},
        ),
      ],
    ));
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({
        'path': path,
        'page': page,
        'total_pages': 1,
        'content': content,
      }),
      toolCallId: callId,
      toolName: 'read_knowledge_file',
    ));
  }

  PromptOptimizerSession newSession() =>
      PromptOptimizerSession(mode: AssistantMode.knowledgeBase);

  Set<int> live(PromptOptimizerSession s, String path) =>
      PromptOptimizerAgent.liveReadPagesForTest(s, path);

  group('_liveReadPages', () {
    test('a fresh read counts, and only for the page actually read', () {
      final session = newSession();
      session.addUserTurn('优化这个提示词');
      recordRead(session, 'a.md', 2);

      expect(live(session, 'a.md'), {2});
      expect(live(session, 'b.md'), isEmpty);
    });

    test('a read whose result carries no content never counts', () {
      final session = newSession();
      session.addUserTurn('go');
      // What a failed read leaves behind. Restore used to replay tool *calls*
      // rather than results, resurrecting these as cache hits.
      session.history.add(LLMMessage(
        role: LLMRole.tool,
        content: jsonEncode({'status': 'error', 'message': 'File not found: a.md'}),
        toolCallId: 'c0',
        toolName: 'read_knowledge_file',
      ));

      expect(live(session, 'a.md'), isEmpty);
    });

    test('the read being executed right now does not count as already read', () {
      // The agent appends the assistant message *with its tool calls* to
      // history before executing them, so anything matching on calls rather
      // than results would find the in-flight read and answer "already in the
      // conversation" for every single read.
      final session = newSession();
      session.addUserTurn('go');
      session.history.add(LLMMessage(
        role: LLMRole.assistant,
        content: '',
        toolCalls: [
          LLMToolCall(
            id: 'c0',
            name: 'read_knowledge_file',
            arguments: {'path': 'a.md', 'page': 1},
          ),
        ],
      ));

      expect(live(session, 'a.md'), isEmpty);
    });

    test('reads elided out of the recent window stop counting', () {
      final session = newSession();
      session.addUserTurn('turn 1');
      recordRead(session, 'a.md', 1);
      // _keepRecentTurns is 6; push the read well past it. This is the elide
      // deadlock: the result the model is told to "refer to" has been replaced
      // by a "Content elided to save context" stub.
      for (int i = 2; i <= 8; i++) {
        session.addUserTurn('turn $i');
      }

      expect(live(session, 'a.md'), isEmpty,
          reason: 'the model can no longer see this read, so it must be allowed '
              'to fetch the file again');
    });

    test('a read still inside the recent window keeps counting', () {
      final session = newSession();
      session.addUserTurn('turn 1');
      recordRead(session, 'a.md', 1);
      session.addUserTurn('turn 2');

      expect(live(session, 'a.md'), {1});
    });

    test('reads folded away by compaction stop counting', () {
      final session = newSession();
      session.addUserTurn('turn 1');
      recordRead(session, 'a.md', 1);

      // What _maybeCompact leaves behind: the head is gone, replaced by a
      // summary that deliberately drops raw tool results.
      session.history
        ..clear()
        ..add(LLMMessage(
          role: LLMRole.user,
          content: '${PromptOptimizerAgent.summaryMarker}\nEarlier: read a.md.',
        ));

      expect(live(session, 'a.md'), isEmpty);
    });
  });
}
