import 'llm/llm_types.dart';
import 'prompt_optimizer_agent.dart';
import 'repositories/assistant_session_repository.dart';

/// One generation-feedback round attached to a prompt version.
class IterationFeedback {
  /// The version number the feedback message itself claims. Kept for display:
  /// it can disagree with the ledger's positional numbering when a session
  /// was restored after compaction (version counting restarts from the
  /// surviving rows — a known quirk); position, not the stated number, is
  /// what binds feedback to the version it followed.
  final int? statedVersion;
  final String imageName;
  final String feedback;

  const IterationFeedback({
    required this.statedVersion,
    required this.imageName,
    required this.feedback,
  });
}

/// One prompt version of the session, with whatever the user reported about
/// the images it generated.
class IterationLedgerEntry {
  final int version;
  final String? note;
  final String prompt;
  final List<IterationFeedback> feedback;

  const IterationLedgerEntry({
    required this.version,
    required this.note,
    required this.prompt,
    required this.feedback,
  });
}

/// Outcome of trying to stage a distill request on a session.
enum KbDistillStageResult {
  staged,

  /// The latest message already is an un-run distill request.
  alreadyPending,

  /// The session has produced no prompt versions — nothing to distill.
  nothingToDistill,

  /// Distilling only makes sense in a knowledge session.
  notKnowledgeSession,

  /// A turn is in flight; staging would race it.
  busy,
}

/// The "knowledge base optimization" half of the assistant: derives the
/// iteration ledger of a tuning session and stages the distill request that
/// asks the agent to fold its lessons back into the knowledge base.
///
/// Everything here is derived from history (live or stored), never tracked:
/// the ledger is a projection of `submit_prompt` calls and
/// `[result_feedback]` messages, so it survives restarts, restores and
/// compaction without any state of its own.
class AssistantKbDistill {
  AssistantKbDistill._();

  /// The full message history of [session], compaction notwithstanding.
  ///
  /// Layer-2 compaction really replaces the in-memory history with a summary,
  /// but the repository keeps the folded rows (`compacted = 1`) — so the
  /// honest source for "what happened in this session" is the stored table,
  /// plus whatever the current turn has not persisted yet. Summary rows are
  /// skipped: they duplicate, lossily, what the flagged rows already say.
  ///
  /// Compaction re-appends the kept tail as fresh rows, so the result can
  /// contain duplicates of tail messages. Deliberately not de-duplicated
  /// here: [buildIterationLedger] de-duplicates semantically (by prompt text
  /// and by feedback identity), which is the only consumer this list has.
  static Future<List<LLMMessage>> loadFullHistory(
    PromptOptimizerSession session, {
    AssistantSessionRepository? repo,
  }) async {
    // Nothing persisted yet — the in-memory history is already complete, and
    // skipping the repository keeps this callable without a database (tests,
    // first turn of a fresh session).
    if (session.persistedCount <= 0) return List.of(session.history);
    final r = repo ?? AssistantSessionRepository();
    final stored = await r.loadMessages(session.id, includeCompacted: true);
    return [
      for (final m in stored)
        if (!m.isSummary) m.message,
      if (session.history.length > session.persistedCount)
        ...session.history.sublist(session.persistedCount),
    ];
  }

  /// Projects [history] into the session's iteration ledger: every prompt
  /// version in order, each with the feedback rounds that followed it.
  ///
  /// Versions are numbered positionally. Two de-duplications make the
  /// projection safe over [loadFullHistory]'s duplicate tail rows: a
  /// `submit_prompt` whose text was already recorded is skipped, and a
  /// feedback identical to one already attached to the same entry is skipped.
  /// Feedback binds to the version *preceding it in the walk* — the stated
  /// version number rides along for display only (see
  /// [IterationFeedback.statedVersion]).
  static List<IterationLedgerEntry> buildIterationLedger(List<LLMMessage> history) {
    // Accumulate into local growable records first, then freeze each into an
    // immutable [IterationLedgerEntry] at the end. The entry's `feedback` list
    // is never mutated after construction, so the type stays safely
    // const-constructible — a `const IterationLedgerEntry(feedback: [])`
    // would otherwise throw on the first `.add` here (unmodifiable list).
    final versions = <({
      int version,
      String? note,
      String prompt,
      List<IterationFeedback> feedback,
    })>[];
    final seenPrompts = <String>{};
    for (final m in history) {
      switch (m.role) {
        case LLMRole.assistant:
          for (final call in m.toolCalls) {
            if (call.name != 'submit_prompt') continue;
            final prompt = call.arguments['prompt']?.toString().trim() ?? '';
            if (prompt.isEmpty || !seenPrompts.add(prompt)) continue;
            final note = call.arguments['note']?.toString().trim();
            versions.add((
              version: versions.length + 1,
              note: (note == null || note.isEmpty) ? null : note,
              prompt: prompt,
              feedback: <IterationFeedback>[],
            ));
          }
        case LLMRole.user:
          final parsed = PromptOptimizerAgent.tryParseResultFeedback(m.content);
          if (parsed == null || versions.isEmpty) continue;
          final target = versions.last;
          final duplicate = target.feedback.any((f) =>
              f.imageName == parsed.imageName && f.feedback == parsed.feedback);
          if (duplicate) continue;
          target.feedback.add(IterationFeedback(
            statedVersion: parsed.promptVersion,
            imageName: parsed.imageName,
            feedback: parsed.feedback,
          ));
        case LLMRole.tool:
        case LLMRole.system:
          break;
      }
    }
    return [
      for (final v in versions)
        IterationLedgerEntry(
          version: v.version,
          note: v.note,
          prompt: v.prompt,
          feedback: List.unmodifiable(v.feedback),
        ),
    ];
  }

  /// Character budget for a non-final prompt excerpt in the rendered ledger.
  static const int earlierPromptExcerptChars = 300;

  /// The final version gets more room — it is the artifact the lessons led to.
  static const int finalPromptExcerptChars = 800;

  /// Renders [entries] as the compact text block embedded in the distill
  /// request. Prompts are excerpted, not repeated in full: the latest prompt
  /// is protected in context anyway (recent window or compaction summary),
  /// and the ledger's job is the trajectory, not the payloads.
  static String renderIterationLedger(List<IterationLedgerEntry> entries) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      final isFinal = identical(entry, entries.last);
      buffer.write('v${entry.version}');
      if (isFinal) buffer.write(' (final)');
      if (entry.note != null) buffer.write(' — ${entry.note}');
      buffer.writeln();
      buffer.writeln('  prompt: ${_excerpt(entry.prompt, isFinal ? finalPromptExcerptChars : earlierPromptExcerptChars)}');
      for (final f in entry.feedback) {
        final versionTag = (f.statedVersion != null && f.statedVersion != entry.version)
            ? ' on v${f.statedVersion}'
            : '';
        buffer.writeln('  user feedback$versionTag (image ${f.imageName}): ${f.feedback}');
      }
    }
    return buffer.toString().trimRight();
  }

  static String _excerpt(String text, int maxChars) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= maxChars ? oneLine : '${oneLine.substring(0, maxChars)}…';
  }

  /// The complete distill-request message, marker included.
  static String composeDistillRequest(List<IterationLedgerEntry> ledger) =>
      '${PromptOptimizerAgent.kbDistillMarker} The user asked to distill this '
      'tuning session\'s lessons into the knowledge base.\n\n'
      'Iteration ledger (derived from the full session, including any part '
      'compacted out of this context):\n'
      '${renderIterationLedger(ledger)}\n\n'
      'Follow the distillation workflow in your system instructions.';

  /// Stages a distill request on [session]: derives the ledger from the full
  /// stored history and appends the request as the next user turn. The caller
  /// enqueues the agent turn afterwards, exactly like a typed message.
  ///
  /// Does not run the model and writes nothing to disk — the distill turn
  /// itself still goes through the staged-edit approval flow.
  static Future<KbDistillStageResult> stageKbDistillRequest({
    required PromptOptimizerSession session,
    AssistantSessionRepository? repo,
  }) async {
    if (!session.usesKnowledgeBase) return KbDistillStageResult.notKnowledgeSession;
    if (session.isRunning) return KbDistillStageResult.busy;
    final history = session.history;
    // Pending means staged-and-not-yet-run: the request is still the literal
    // last message. Once the turn has run (assistant/tool messages follow),
    // a fresh request is legitimate — the user may distill again after more
    // iteration.
    if (history.isNotEmpty &&
        history.last.role == LLMRole.user &&
        history.last.content.startsWith(PromptOptimizerAgent.kbDistillMarker)) {
      return KbDistillStageResult.alreadyPending;
    }
    final ledger = buildIterationLedger(await loadFullHistory(session, repo: repo));
    if (ledger.isEmpty) return KbDistillStageResult.nothingToDistill;
    // A distill click while a question card is pending answers it the same
    // way free text does — pair the dangling call so the history stays valid.
    final pendingAsk = session.pendingAskUser;
    if (pendingAsk != null) {
      PromptOptimizerAgent.resolvePendingAskUserAsFreeText(
        session: session,
        callId: pendingAsk.callId,
      );
    }
    session.addKbDistillTurn(composeDistillRequest(ledger));
    return KbDistillStageResult.staged;
  }
}
