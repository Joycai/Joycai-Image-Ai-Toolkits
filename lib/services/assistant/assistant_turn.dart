part of 'prompt_optimizer_agent.dart';

/// The system prompt for this turn's mode — built once per turn.
String _systemPromptFor({
  required bool distillTurn,
  required bool editMode,
  required bool knowledgeMode,
  required String? knowledgeEntryContent,
  required String? systemPrompt,
  required int refCount,
  required bool forceView,
}) {
  return distillTurn
      // Distill outranks the edit prompt even in knowledgeEdit mode: the
      // deliverable of this turn is distilled lessons, and the distillation
      // guardrails (scope, provenance, contradictions) only live here.
      // canWrite must be passed, not assumed — with writes disabled the
      // model still runs the review but must present findings as text.
      ? _buildKnowledgeDistillSystemPrompt(knowledgeEntryContent!, canWrite: editMode)
      : editMode
          ? _buildKnowledgeEditSystemPrompt(
              knowledgeEntryContent!, refCount, forceView)
          : knowledgeMode
              ? _buildKnowledgeSystemPrompt(
                  knowledgeEntryContent!, refCount, forceView)
              : _buildSystemPrompt(systemPrompt, refCount, forceView);
}

/// Warns, once per turn, when the knowledge base's file map alone fills a
/// large share of the window.
void _warnIfSystemPromptCrowds(
  PromptOptimizerSession session,
  String systemPromptText, {
  required bool knowledgeMode,
  required int? contextWindow,
  required void Function(String message)? onLog,
}) {
  // Say something while there is still something to say. Compaction only
  // folds history, so it can never shrink this — past a certain size the turn
  // is doomed and the only signal would be the provider's own error. A
  // warning, not a failure: with the window itself picked off a preset
  // slider, refusing to run would break setups that work today.
  if (knowledgeMode && contextWindow != null && contextWindow > 0) {
    final windowChars = contextWindow *
        (session.observedCharsPerToken ?? ContextBudget.charsPerToken);
    if (systemPromptText.length > windowChars * _systemPromptWarnShare) {
      onLog?.call('The knowledge base file map fills '
          '${(systemPromptText.length / windowChars * 100).round()}% of this '
          "model's context window, and is re-sent every request.");
      session._addEntry(OptimizerChatEntry(
        kind: OptimizerEntryKind.notice,
        text: PromptOptimizerAgent.kbEntryTooLargeNoticeToken,
      ));
    }
  }
}

/// Everything before the first request of a turn: make the history
/// sendable, record the user's decisions on staged edits, persist, and
/// compact if needed. False when the user stopped the turn meanwhile.
Future<bool> _prepareTurn(
  PromptOptimizerSession session,
  List<Map<String, String>> referenceImages,
  AssistantSessionRepository repo, {
  required dynamic modelIdentifier,
  required String systemPromptText,
  required String? contextId,
  required int? contextWindow,
  required double contextRatio,
  required void Function(String message)? onLog,
  required bool Function()? isCancelled,
}) async {
  // Make the history sendable before anything else reads it. The dangling
  // ask_user guard runs first so its own semantics (pair in place, or strip
  // a pre-rail call) decide that case; the generic repair then covers
  // everything else a restore or an interrupted write can leave behind.
  _cancelDanglingAskUser(session);
  if (session._repairToolCallPairing()) {
    onLog?.call('Repaired tool-call pairing in the conversation history.');
  }
  // What the user did with the model's staged edits since it last spoke
  // (invariant 11). After the pairing work, so it never lands between a
  // call and its result; before persistence, so it is saved with the turn.
  final outcomes = _drainKbEditOutcomes(session);
  if (outcomes != null) {
    session.history.add(LLMMessage(role: LLMRole.user, content: outcomes));
  }
  // Persist the pending user turn, then compact if the history has grown
  // past the context budget. Persistence failures never block the turn.
  try {
    await PromptOptimizerAgent._syncPersistence(session, referenceImages, repo);
    await _maybeCompact(
      session,
      modelIdentifier,
      repo,
      contextId,
      onLog,
      systemPrompt: systemPromptText,
      contextWindow: contextWindow,
      contextRatio: contextRatio,
      isCancelled: isCancelled,
    );
  } on LLMCancelled {
    // Ahead of the catch-all so a stop pressed during compaction is not
    // logged as "Session persistence failed". The turn loop below would
    // return on its first check anyway; this only keeps the console
    // honest about what happened.
    return false;
  } catch (e) {
    onLog?.call('Session persistence failed (continuing without it): $e');
  }
  return true;
}

/// Runs one tool call of a batch and returns its result, or null when it
/// staged an ask_user card — that call stays unpaired and the caller ends
/// the turn. A throwing executor becomes an error result. The caller
/// handles cancellation, which is sticky across the batch.
Future<Map<String, dynamic>?> _dispatchToolCall(
  LLMToolCall call,
  List<LLMToolCall> batch,
  PromptOptimizerSession session, {
  required Set<String> offered,
  required dynamic modelIdentifier,
  required dynamic kbSubAgentModelIdentifier,
  required int? kbSubAgentContextWindow,
  required String? knowledgeRoot,
  required Set<String> delegateKinds,
  required List<Map<String, String>> referenceImages,
  required List<Map<String, String>> pendingViews,
  required bool forceView,
  required String systemPromptText,
  required int? contextWindow,
  required String? contextId,
  required void Function(String message)? onLog,
  required bool Function()? isCancelled,
  required void Function() onContextExhausted,
}) async {
  Map<String, dynamic> result;
  if (!offered.contains(call.name)) {
    // Standard 07 §4.6 rule 3: only a tool offered in this request
    // may run. A model can name any tool it has ever seen — a
    // delegate it was never given, a write tool in a read-only
    // session, a tool withdrawn when the window filled — and every
    // executor below would otherwise act on it. The executors keep
    // their own precondition checks as defence in depth.
    onLog?.call('Tool call rejected: "${call.name}" was not offered in this request.');
    result = {
      'status': 'error',
      'message': 'Tool "${call.name}" was not offered in this request, so it '
          'did not run. '
          '${offered.isEmpty ? 'No tools are available right now — answer in plain text.' : 'Available tools: ${offered.join(', ')}.'}',
    };
  } else if (call.name == 'ask_user') {
    if (!PromptOptimizerAgent.canStageAskUser(batch)) {
      result = {
        'status': 'error',
        'message': 'ask_user must be the only tool call in a message, '
            'so this question was NOT shown to the user. The other '
            'calls in this message ran normally — ask again on its own '
            'in your next message.',
      };
    } else {
      final questions = AskUserQuestion.tryParse(call.arguments['questions']);
      if (questions == null) {
        result = {
          'status': 'error',
          'message': 'Invalid questions payload. Pass 1-4 questions, '
              'each with a non-empty header, a non-empty question, and '
              '2-4 options with non-empty labels.',
        };
      } else {
        onLog?.call('Tool call: ask_user (${questions.length} question(s)) '
            '— waiting for the user.');
        session._stageAskUser(call.id, questions);
        return null; // Deliberately NO paired result — the caller skips pairing.
      }
    }
  } else if (call.name == 'delegate') {
    // Async (it runs a whole nested agent), so it lives here rather
    // than in the synchronous _executeTool switch. Same pairing
    // contract: any escape becomes an error result.
    try {
      // The sub-agent runs on the dedicated binding when one is
      // configured, otherwise on the session's own model — with the
      // matching window, so its read budget is its own.
      result = await _executeDelegate(
        call,
        session,
        kbSubAgentModelIdentifier ?? modelIdentifier,
        knowledgeRoot,
        availableKinds: delegateKinds,
        referenceImages: referenceImages,
        contextWindow: kbSubAgentModelIdentifier != null
            ? kbSubAgentContextWindow
            : contextWindow,
        contextId: contextId,
        onLog: onLog,
        isCancelled: isCancelled,
      );
    } catch (e) {
      onLog?.call('Tool delegate failed: $e');
      result = {
        'status': 'error',
        'message': 'Tool delegate failed: $e',
      };
    }
  } else if (call.name == 'write_knowledge_file') {
    // Async once per-edit confirmation can be off, so it sits here
    // beside delegate and read_note rather than in the synchronous
    // _executeTool switch.
    try {
      result = await _executeWriteKnowledge(call, session, knowledgeRoot, onLog);
    } catch (e) {
      onLog?.call('Tool write_knowledge_file failed: $e');
      result = {
        'status': 'error',
        'message': 'Tool write_knowledge_file failed: $e',
      };
    }
  } else if (call.name == 'read_note') {
    // Async (note store lives in SQLite), so alongside delegate
    // rather than in the synchronous _executeTool switch.
    try {
      result = await _executeReadNote(
        call,
        session,
        systemPrompt: systemPromptText,
        contextWindow: contextWindow,
        onLog: onLog,
      );
    } catch (e) {
      onLog?.call('Tool read_note failed: $e');
      result = {
        'status': 'error',
        'message': 'Tool read_note failed: $e',
      };
    }
  } else {
    try {
      result = _executeTool(
        call,
        referenceImages,
        session,
        pendingViews,
        forceView,
        knowledgeRoot,
        onLog,
        systemPrompt: systemPromptText,
        contextWindow: contextWindow,
        onContextExhausted: onContextExhausted,
      );
    } catch (e) {
      onLog?.call('Tool ${call.name} failed: $e');
      result = {
        'status': 'error',
        'message': 'Tool ${call.name} failed: $e',
      };
    }
  }
  return result;
}

/// The outcomes record that opens a turn (invariant 11, standard 08 §3.6):
/// every staged edit decided since the last report, or null when there is
/// nothing new. Marks each listed edit reported, so it is said once.
///
/// Facts only, no instruction — it is persisted, and a persisted "do X"
/// would keep steering every later turn (11 §21).
String? _drainKbEditOutcomes(PromptOptimizerSession session) {
  final lines = <String>[];
  for (final e in session.transcript) {
    if (e.kind != OptimizerEntryKind.kbEdit || e.editId == null) continue;
    final state = e.editState;
    if (state == null || state == KbEditState.pending) continue;
    if (!session._reportedKbEditIds.add(e.editId!)) continue;
    final path = e.targetPath ?? e.text;
    final error = e.editError;
    lines.add(switch (state) {
      KbEditState.applied => '- $path: applied by the user — it is now on disk.',
      KbEditState.rejected => '- $path: rejected by the user — it was not written.',
      KbEditState.failed =>
        '- $path: failed to apply — it was not written${error == null ? '' : ' ($error)'}.',
      KbEditState.pending => '',
    });
  }
  if (lines.isEmpty) return null;
  return '${PromptOptimizerAgent.kbEditOutcomesMarker} Since your last turn, the user decided on '
      'these staged knowledge-base edits:\n${lines.join('\n')}';
}
