import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';

/// Which knowledge files the assistant's current answer rests on.
///
/// Shown to the user as "cited this round", so it has to mean something they
/// can check: a file named here should be one the model actually still has in
/// front of it. Derived from tool results rather than tracked in a set, for
/// the same reason every other "what has been read" question in this
/// subsystem is — see the deadlock documented in
/// `test/optimizer_kb_liveness_test.dart`.
void main() {
  /// The assistant call + tool result pair the agent writes for one
  /// `read_knowledge_file` that actually returned content.
  void recordRead(PromptOptimizerSession session, String path, {int page = 1}) {
    final callId = 'call_${session.history.length}';
    session.history.add(LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [
        LLMToolCall(id: callId, name: 'read_knowledge_file', arguments: {'path': path, 'page': page}),
      ],
    ));
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({'path': path, 'page': page, 'total_pages': 1, 'content': 'rule body'}),
      toolCallId: callId,
      toolName: 'read_knowledge_file',
    ));
  }

  /// What the agent returns when the model asks for a page it already has.
  void recordCacheHit(PromptOptimizerSession session, String path) {
    final callId = 'call_${session.history.length}';
    session.history.add(LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [
        LLMToolCall(id: callId, name: 'read_knowledge_file', arguments: {'path': path, 'page': 1}),
      ],
    ));
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({'status': 'ok', 'path': path, 'note': 'already in the conversation'}),
      toolCallId: callId,
      toolName: 'read_knowledge_file',
    ));
  }

  void recordFailedRead(PromptOptimizerSession session, String path) {
    final callId = 'call_${session.history.length}';
    session.history.add(LLMMessage(
      role: LLMRole.assistant,
      content: '',
      toolCalls: [
        LLMToolCall(id: callId, name: 'read_knowledge_file', arguments: {'path': path, 'page': 1}),
      ],
    ));
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({'status': 'error', 'message': 'Directory not found: $path'}),
      toolCallId: callId,
      toolName: 'read_knowledge_file',
    ));
  }

  void userSays(PromptOptimizerSession session, String text) {
    session.history.add(LLMMessage(role: LLMRole.user, content: text));
  }

  PromptOptimizerSession newSession() => PromptOptimizerSession(mode: AssistantMode.knowledgeBase);

  List<String> cited(PromptOptimizerSession s) => PromptOptimizerAgent.citedKnowledgeFiles(s);

  test('a file read this turn is cited', () {
    final s = newSession();
    userSays(s, 'make it cinematic');
    recordRead(s, '04_cosplay.md');

    expect(cited(s), ['04_cosplay.md']);
  });

  test('files are listed in the order the agent consulted them', () {
    // The list reads as a trail of the agent's work, so order carries meaning.
    final s = newSession();
    userSays(s, 'go');
    recordRead(s, '07_footwear.md');
    recordRead(s, '04_cosplay.md');

    expect(cited(s), ['07_footwear.md', '04_cosplay.md']);
  });

  test('a file read once is cited once, however many pages', () {
    final s = newSession();
    userSays(s, 'go');
    recordRead(s, '04_cosplay.md', page: 1);
    recordRead(s, '04_cosplay.md', page: 2);

    expect(cited(s), ['04_cosplay.md']);
  });

  test('a cache hit still counts — the model is using the file, not ignoring it', () {
    // The whole reason the agent puts a `path` on the "already in the
    // conversation" result. Without it, a template the answer leans on
    // vanishes from the list the moment the model stops re-reading it.
    final s = newSession();
    userSays(s, 'first');
    recordRead(s, '04_cosplay.md');
    userSays(s, 'second');
    recordCacheHit(s, '04_cosplay.md');

    expect(cited(s), contains('04_cosplay.md'));
  });

  test('a failed read is not a citation', () {
    // It carries no path and no content; claiming the answer rests on a file
    // the agent could not open would be a lie the user cannot check.
    final s = newSession();
    userSays(s, 'go');
    recordFailedRead(s, 'nope.md');

    expect(cited(s), isEmpty);
  });

  test('a read still inside the live window survives a later turn', () {
    // Grounded-in, not read-this-turn: the file is still going out with every
    // request, so it is still holding the answer up.
    final s = newSession();
    userSays(s, 'first');
    recordRead(s, '04_cosplay.md');
    userSays(s, 'second');

    expect(cited(s), ['04_cosplay.md']);
  });

  test('a read that has fallen out of the live window is dropped', () {
    // Once layer 1 elides it, the model genuinely no longer has it, so the
    // claim would stop being true. This is the property that keeps the list
    // honest rather than ever-growing.
    final s = newSession();
    userSays(s, 'first');
    recordRead(s, 'ancient.md');
    for (var i = 0; i < 6; i++) {
      userSays(s, 'turn $i');
      recordRead(s, 'recent_$i.md');
    }

    expect(cited(s), isNot(contains('ancient.md')));
    expect(cited(s), contains('recent_5.md'));
  });

  test('other knowledge tools are not citations', () {
    // Listing a directory is not reading a document.
    final s = newSession();
    userSays(s, 'go');
    s.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({'files': [], 'path': '07_footwear'}),
      toolCallId: 'c1',
      toolName: 'list_knowledge_files',
    ));

    expect(cited(s), isEmpty);
  });

  test('a session that read nothing cites nothing', () {
    final s = newSession();
    userSays(s, 'just chat');

    expect(cited(s), isEmpty);
  });
}
