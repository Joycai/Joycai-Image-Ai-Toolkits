part of 'prompt_optimizer_agent.dart';

/// [PromptOptimizerAgent.repairToolCallPairing], with each output's index in the input (null for
/// a stub) so a caller can rebase indices it holds.
List<({LLMMessage message, int? origin})> _repairPairingWithOrigins(
    List<LLMMessage> history) {
  final out = <({LLMMessage message, int? origin})>[];
  int i = 0;
  while (i < history.length) {
    final m = history[i];
    if (m.role == LLMRole.tool) {
      // Every legitimate result is consumed by its batch below.
      i++;
      continue;
    }
    if (m.role != LLMRole.assistant) {
      out.add((message: m, origin: i));
      i++;
      continue;
    }

    final seen = <String>{};
    final calls = [
      for (final c in m.toolCalls)
        if (c.id.isNotEmpty && seen.add(c.id)) c,
    ];
    if (calls.isEmpty && m.content.trim().isEmpty) {
      // Nothing to send. Its results, if any, fall through as orphans.
      i++;
      continue;
    }
    final assistant = calls.length == m.toolCalls.length
        ? m
        : LLMMessage(
            role: LLMRole.assistant,
            content: m.content,
            reasoningContent: m.reasoningContent,
            reasoningFieldName: m.reasoningFieldName,
            reasoningSignature: m.reasoningSignature,
            rawThinkingBlocks: m.rawThinkingBlocks,
            rawThinkingModelId: m.rawThinkingModelId,
            // The verbatim copies name the stripped calls.
            rawContentBlocks: null,
            rawModelParts: null,
            rawResponseItems: null,
            toolCalls: calls,
          );
    out.add((message: assistant, origin: i));
    i++;

    final ids = {for (final c in calls) c.id};
    final answered = <String>{};
    while (i < history.length && history[i].role == LLMRole.tool) {
      final t = history[i];
      final id = t.toolCallId;
      if (id != null && ids.contains(id) && answered.add(id)) {
        out.add((message: t, origin: i));
      }
      i++;
    }
    final atEnd = i >= history.length;
    for (final c in calls) {
      if (answered.contains(c.id)) continue;
      if (atEnd &&
          c.name == 'ask_user' &&
          AskUserQuestion.tryParse(c.arguments['questions']) != null) {
        continue; // The suspended question — see the dartdoc above.
      }
      out.add((
        message: LLMMessage(
          role: LLMRole.tool,
          content: jsonEncode({'status': 'not_run', 'message': PromptOptimizerAgent.notRunStubMessage}),
          toolCallId: c.id,
          toolName: c.name,
        ),
        origin: null,
      ));
    }
  }
  return out;
}

/// Pairs the dangling `ask_user` call [callId] with [result].
///
/// Appends a tool message when that still lands inside the call's own batch
/// — the normal case, which [PromptOptimizerAgent.canStageAskUser] guarantees. It does not hold
/// for a history written by a build that predates that rail, where a
/// `view_image` attachment could sit between the call and here; appending
/// there would produce the exact ordering providers reject. In that case the
/// call is stripped from the assistant message instead — the question is
/// cancelled either way — and [fallback], if given, is appended as a user
/// message so the user's input is not silently dropped.
///
/// The repair is in place (same index, same list length), so
/// [PromptOptimizerSession.persistedCount] stays a valid count. The stored
/// row keeps the old shape, but this runs at the top of every turn, so what
/// goes on the wire is repaired every time.
void _pairDanglingAskUser(
  PromptOptimizerSession session,
  String callId,
  Map<String, dynamic> result, {
  String? fallback,
}) {
  final history = session.history;
  int owner = -1;
  for (int i = history.length - 1; i >= 0; i--) {
    if (history[i].toolCalls.any((c) => c.id == callId)) {
      owner = i;
      break;
    }
  }
  if (owner < 0) return;

  final adjacent = history.skip(owner + 1).every((m) => m.role == LLMRole.tool);
  if (adjacent) {
    history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode(result),
      toolCallId: callId,
      toolName: 'ask_user',
    ));
  } else {
    final owning = history[owner];
    history[owner] = LLMMessage(
      role: LLMRole.assistant,
      content: owning.content,
      // Verbatim, like everywhere else this rewrites an assistant message:
      // the ① family echo-back contract does not care why it was rewritten.
      reasoningContent: owning.reasoningContent,
      reasoningFieldName: owning.reasoningFieldName,
      reasoningSignature: owning.reasoningSignature,
      rawThinkingBlocks: owning.rawThinkingBlocks,
      rawThinkingModelId: owning.rawThinkingModelId,
      // Stripping a call rewrites the tool_use list, so the verbatim copy
      // can no longer stand for this turn — it is dropped and the turn is
      // rebuilt from the fields, like any pre-capture history. ③'s verbatim
      // parts and ②'s verbatim items carry the removed call too, and go for
      // the same reason.
      rawContentBlocks: null,
      rawModelParts: null,
      rawResponseItems: null,
      toolCalls: [
        for (final c in owning.toolCalls)
          if (c.id != callId) c,
      ],
    );
    session._carryStaleMarker(owning, history[owner]);
    if (fallback != null) {
      history.add(LLMMessage(role: LLMRole.user, content: fallback));
    }
  }
}

/// Self-healing guard, run at the top of every turn: a dangling ask_user
/// call must never reach a provider (both endpoints reject an unpaired tool
/// call). The normal paths pair it before enqueueing a turn — the answer
/// card via [PromptOptimizerAgent.answerAskUser], or free text via
/// [PromptOptimizerAgent.resolvePendingAskUserAsFreeText] — so a turn starting while one is still
/// pending means some other path got here (e.g. Retry on an old error).
/// Cancel the question so the history is valid again.
void _cancelDanglingAskUser(PromptOptimizerSession session) {
  final dangling = session.pendingAskUser;
  if (dangling == null) return;
  _pairDanglingAskUser(session, dangling.callId, {
    'status': 'cancelled',
    'message': 'The question was not answered.',
  });
  session._resolveAskUser(dangling.callId, AskUserState.dismissed);
}
