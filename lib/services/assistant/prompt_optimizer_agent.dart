import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../models/prompt.dart';
import '../../models/result_feedback.dart';
import 'assistant_context_usage.dart';
import '../db/database_service.dart';
import 'knowledge_base_service.dart';
import '../llm/context_budget.dart';
import '../llm/image_compression.dart';
import '../llm/llm_dispatcher.dart';
import '../llm/llm_service.dart';
import '../llm/llm_types.dart';
import '../db/repositories/assistant_note_repository.dart';
import '../db/repositories/assistant_session_repository.dart';
import 'sub_agent_runner.dart';

part 'assistant_chat_entries.dart';
part 'assistant_context_window.dart';
part 'assistant_history_repair.dart';
part 'assistant_system_prompts.dart';
part 'assistant_tool_calls.dart';
part 'assistant_toolset.dart';
part 'assistant_turn.dart';
part 'prompt_optimizer_session.dart';

/// Interactive prompt-optimization agent (tool-use loop).
///
/// The model is given three tools:
///  * `list_reference_images` — metadata of the user's reference images.
///  * `view_image`            — attach one reference image on demand, so
///                              images cost tokens only when actually needed.
///  * `submit_prompt`         — deliver an optimized prompt (the only channel
///                              for results; keeps chat text and deliverable
///                              cleanly separated).
///  * `ask_user`              — ask structured clarifying questions; the turn
///                              suspends with the call left dangling until the
///                              user answers (see [answerAskUser]).
///
/// In [AssistantMode.knowledgeBase] two more tools are registered:
///  * `list_knowledge_files` / `read_knowledge_file` — progressive-disclosure
///    access to the user's local knowledge base folder.
///
/// Unlike [AiRenameAgent] this is conversational: the session accumulates
/// turns and the user can iterate ("make it more cinematic") with full
/// context preserved.
class PromptOptimizerAgent {
  static const int _maxTurns = 12;

  /// Marker prefixes used to recognize synthetic messages in the history.
  static const String viewResultMarker = '[view_image result]';
  static const String summaryMarker = '[Conversation summary]';

  /// Heads the latest submitted prompt inside a compaction summary message.
  /// The app appends it there itself: the summarizer used to be asked to
  /// reproduce "the LATEST submitted prompt in full", a 6–8K-token document
  /// re-typed by a non-streaming call whose deadline assumed 4096 — and the
  /// app already holds that text, byte for byte, in the folded history.
  static const String latestPromptMarker = '[Latest submitted prompt]';

  /// Marker of a user turn reporting a generation result — see
  /// [PromptOptimizerSession.addResultFeedback] for the wire format.
  static const String resultFeedbackMarker = '[result_feedback]';

  /// Marker of the user's "distill this session into the knowledge base"
  /// request. Unlike [viewResultMarker]/[summaryMarker] messages, both this
  /// and [resultFeedbackMarker] ARE real user turns ([_isRealUserTurn]): they
  /// open a turn the user initiated, so they count toward the protected
  /// window and boundary math like any typed message.
  static const String kbDistillMarker = '[kb_distill]';

  /// Marker of the synthetic record of staged-edit outcomes that opens a turn
  /// (invariant 11). Like [viewResultMarker] it is not a real user turn.
  static const String kbEditOutcomesMarker = '[kb_edit_outcomes]';

  /// What a task-preset session runs on when no preset is chosen — the
  /// built-in one. Public because the panel shows it (`A3d 4b`): a default
  /// the user cannot see is a default they cannot judge, or copy from.
  static const String builtinPresetInstructions =
      'You are an expert prompt engineer for AI image and video generation.';

  /// Transcript-notice tokens, mapped to localized strings at render time.
  static const String compactedNoticeToken = '__compacted__';
  static const String imageMissingNoticeToken = '__image_missing__';
  static const String kbEntryTooLargeNoticeToken = '__kb_entry_too_large__';
  static const String kbDistillNoticeToken = '__kb_distill__';

  /// The divider a knowledge session leaves when its use is switched —
  /// see [PromptOptimizerSession.switchKnowledgeUse].
  static const String kbUseMaintainNoticeToken = '__kb_use_maintain__';
  static const String kbUseWriteNoticeToken = '__kb_use_write__';

  /// A turn used every round and the final, tools-free one still produced no
  /// answer (standard 07 §3.8).
  static const String roundLimitNoticeToken = '__round_limit__';

  /// Error-entry text token: [maxTruncatedRounds] consecutive replies were
  /// cut at the output limit while carrying tool calls, so the turn stopped
  /// rather than burn its remaining rounds on the same cut. The UI renders
  /// the explanation and a jump to the model's max-output setting.
  static const String truncationStopNoticeToken = '__truncation_stop__';

  /// Parses a [resultFeedbackMarker] message back into its parts, or null when
  /// the header line is not the JSON [PromptOptimizerSession.addResultFeedback]
  /// writes. Shared by transcript restore, the iteration ledger, and the
  /// result-image metadata in `list_reference_images` — one format, one parser.
  static ({
    int? promptVersion,
    String imageName,
    String feedback,
    bool? satisfied,
    List<ResultFeedbackReason> reasons,
  })? tryParseResultFeedback(String content) {
    if (!content.startsWith(resultFeedbackMarker)) return null;
    final rest = content.substring(resultFeedbackMarker.length);
    final newline = rest.indexOf('\n');
    final headerLine = (newline < 0 ? rest : rest.substring(0, newline)).trim();
    final feedback = newline < 0 ? '' : rest.substring(newline + 1).trim();
    try {
      final header = jsonDecode(headerLine);
      if (header is! Map) return null;
      final image = header['image']?.toString() ?? '';
      if (image.isEmpty) return null;
      final rawVersion = header['prompt_version'];
      final version =
          rawVersion is int ? rawVersion : int.tryParse(rawVersion?.toString() ?? '');
      // Absent on reports older than the rating (`3b`); an unknown value
      // reads as unrated rather than as a verdict the user never gave.
      final satisfied = switch (header['rating']) {
        'satisfied' => true,
        'unsatisfied' => false,
        _ => null,
      };
      final rawReasons = header['reasons'];
      final reasons = <ResultFeedbackReason>[
        if (rawReasons is List)
          for (final id in rawReasons) ?ResultFeedbackReason.fromWireId(id.toString()),
      ];
      return (
        promptVersion: version,
        imageName: image,
        feedback: feedback,
        satisfied: satisfied,
        reasons: reasons,
      );
    } catch (_) {
      return null;
    }
  }

  /// Result-image metadata derived from [history], keyed by image name:
  /// which prompt version the image came from and what the user said about
  /// it (the latest feedback wins when an image is reported on twice).
  ///
  /// Derived per call rather than stored anywhere — feedback lives in the
  /// history as [resultFeedbackMarker] messages, so this works identically
  /// for live and restored sessions and nothing can go stale.
  static Map<String, ({int? promptVersion, String feedback})> resultImageInfoByName(
      List<LLMMessage> history) {
    final info = <String, ({int? promptVersion, String feedback})>{};
    for (final m in history) {
      if (m.role != LLMRole.user) continue;
      final parsed = tryParseResultFeedback(m.content);
      if (parsed == null) continue;
      info[parsed.imageName] =
          (promptVersion: parsed.promptVersion, feedback: parsed.feedback);
    }
    return info;
  }

  static const String retentionSettingKey = 'assistant_session_retention';
  static const int defaultRetention = 20;

  /// Fraction of the model's context window at which the conversation is
  /// summarized to make room ("hard summary limit").
  ///
  /// The headroom above it is not waste — it is what funds reading a knowledge
  /// file in one piece mid-turn, which compaction then reclaims at the next
  /// turn boundary. See [ContextBudget.readCapChars].
  static const String contextRatioSettingKey = 'assistant_context_ratio';

  /// Settings key for the knowledge sub-agent opt-in (default off). Read by
  /// the task executor and the settings screen; the agent itself only sees
  /// the resolved boolean via [runTurn]'s `kbSubAgentEnabled`.
  static const String kbSubAgentSettingKey = 'enable_kb_subagent';

  /// Settings key for the sub-agent's dedicated model binding: the model's
  /// DB id as a string, absent/empty meaning "follow the session's model".
  /// Resolved by the task executor; a binding pointing at a deleted model
  /// disables delegation for the turn (with a log) rather than silently
  /// falling back — the settings screen warns in place.
  static const String kbSubAgentModelSettingKey = 'kb_subagent_model';
  static const double defaultContextRatio = 0.6;

  /// Whether the conversation should be summarized before the next request.
  ///
  /// Pure so it can be pinned without a database or a live model.
  static bool shouldCompact({
    required int occupied,
    required int budgetChars,
    required int messageCount,
  }) =>
      occupied >= budgetChars || messageCount > _compactMaxMessages;

  /// Where to fold: the history before the returned index becomes the
  /// summary. Null means do not compact this turn.
  ///
  /// When only the message count tripped the trigger ([sizeTriggered] false),
  /// the fold is to the recent window, exactly as before — occupancy is not
  /// the problem, so there is no target to reach. When size tripped it, the
  /// fold keeps the most recent turns whose projected occupancy — the tail as
  /// [_trimForSend] will send it, plus [_summaryAllowanceChars] — fits under
  /// [_retainTargetShare] of [budgetChars]: never more than [_keepRecentTurns],
  /// never fewer than [_minKeepTurns], and down to that floor anyway when
  /// nothing fits (freeing most of the room beats freeing none).
  ///
  /// Skipped when the head would be just an existing summary plus at most one
  /// turn. Re-summarizing a summary to reclaim a single turn is the
  /// compact-every-turn loop, and each pass invalidates the prompt-cache prefix.
  @visibleForTesting
  static int? compactionBoundary(
    List<LLMMessage> history, {
    required String systemPrompt,
    required int budgetChars,
    required bool sizeTriggered,

    /// The latest delivery's index and size (`_latestSubmittedPrompt`). A
    /// fold that takes it appends its text to the summary, so the projected
    /// tail includes it whenever the candidate boundary lies past it —
    /// otherwise a 6–8K-token prompt lands on top of the retention target
    /// and the trigger/target gap is never restored.
    int? carriedPromptIndex,
    int? carriedPromptChars,
  }) {
    final starts = [
      for (int i = 0; i < history.length; i++)
        if (_isRealUserTurn(history[i])) i,
    ];

    final int keep;
    if (!sizeTriggered) {
      if (starts.length <= _keepRecentTurns) return null;
      keep = _keepRecentTurns;
    } else {
      if (starts.length <= _minKeepTurns) return null;
      final maxKeep =
          starts.length - 1 < _keepRecentTurns ? starts.length - 1 : _keepRecentTurns;
      final target = (budgetChars * _retainTargetShare).floor();
      var fits = _minKeepTurns;
      for (int k = maxKeep; k >= _minKeepTurns; k--) {
        final candidate = starts[starts.length - k];
        final tail = history.sublist(candidate);
        final carried = carriedPromptIndex != null && carriedPromptIndex < candidate
            ? (carriedPromptChars ?? 0)
            : 0;
        final projected =
            occupiedChars(systemPrompt, _trimForSend(tail)) + _summaryAllowanceChars + carried;
        if (projected <= target) {
          fits = k;
          break;
        }
      }
      keep = fits;
    }

    final boundary = starts[starts.length - keep];
    if (boundary <= 1) return null;
    final foldedTurns = starts.length - keep;
    final headIsSummary = history.first.role == LLMRole.user &&
        history.first.content.startsWith(summaryMarker);
    if (headIsSummary && foldedTurns <= 1) return null;
    return boundary;
  }

  /// Replaces every model request the agent makes — the turn loop's and
  /// compaction's — so the loop's invariants can be pinned without a network.
  /// Null in production.
  @visibleForTesting
  static AgentRequestFn? debugRequestOverride;

  static Future<LLMResponse> _request({
    required dynamic modelIdentifier,
    required List<LLMMessage> messages,
    List<LLMTool>? tools,
    String? contextId,
    required Map<String, dynamic> options,
    required bool useStream,
    bool Function()? isCancelled,
    void Function(int chars)? onToolArgumentChars,
  }) {
    final override = debugRequestOverride;
    if (override != null) return override(messages, tools, options);
    return LLMService().request(
      modelIdentifier: modelIdentifier,
      messages: messages,
      tools: tools,
      contextId: contextId,
      options: options,
      useStream: useStream,
      isCancelled: isCancelled,
      onToolArgumentChars: onToolArgumentChars,
    );
  }

  /// Live sessions by id, so the task-queue executor can resolve the session
  /// referenced by a queued task.
  static final Map<String, PromptOptimizerSession> sessions = {};

  /// Delegation to a sub-agent, offered when the user has enabled it in
  /// Settings (default off) and at least one kind's preconditions hold.
  ///
  /// The schema is built per hand-out (never a mutated shared constant):
  /// the `kind` enum lists only the kinds available to *this* session, and
  /// each kind's private parameter (`paths` for knowledge, `image_id` for
  /// draft) appears only when its kind does — a field describing an
  /// unavailable capability reads as an instruction to try it.
  ///
  /// The description teaches the zero-context-inheritance rule: the
  /// sub-agent sees nothing of this conversation, so the brief must stand
  /// alone. Deliberately additive: `read_knowledge_file` and `view_image`
  /// stay in the main toolset — targeted work is day-to-day, and the
  /// read-before-write rail is anchored on the *main* history's live reads.
  @visibleForTesting
  static LLMTool delegateToolFor(Set<String> kinds) {
    final hasKnowledge = kinds.contains('knowledge');
    final hasDraft = kinds.contains('draft');
    return LLMTool(
      name: 'delegate',
      description: 'Hand a task to a sub-agent that works in its own '
          'separate context. The sub-agent sees NOTHING of this conversation '
          '— write everything it needs to know into "task". '
          '${hasKnowledge ? 'kind "knowledge": broad research across '
              'knowledge-base files (for reading one specific file you '
              'already know, call read_knowledge_file directly). ' : ''}'
          '${hasDraft ? 'kind "draft": study ONE reference image (image_id) '
              'and draft a prompt fragment for it per your brief — use it '
              'to cover many reference images without viewing them all '
              'yourself. ' : ''}'
          'Returns a findings summary (full text retrievable via read_note).',
      parameters: {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': [if (hasDraft) 'draft', if (hasKnowledge) 'knowledge'],
            'description': 'The kind of sub-agent.',
          },
          'task': {
            'type': 'string',
            'description': 'The complete, self-contained brief.',
          },
          if (hasKnowledge)
            'paths': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'knowledge only, optional: knowledge-base file '
                  'paths (relative) the sub-agent should start from.',
            },
          if (hasDraft)
            'image_id': {
              'type': 'integer',
              'description': 'draft only, required: the reference image id '
                  '(same ids as list_reference_images / view_image).',
            },
        },
        'required': ['kind', 'task'],
      },
    );
  }

  /// The toolset for one request, assembled from the session's mode and the
  /// turn's state. Pure so the routing rules are pinnable in tests:
  ///
  ///  * capability routing is a toolset change, never a prompt suggestion;
  ///  * `delegate` is additive to the knowledge/image tools, never a
  ///    replacement, and appears when any kind in [delegateKinds] is
  ///    available (the kinds themselves are decided by the caller: knowledge
  ///    needs a knowledge session, draft needs reference images and an
  ///    image-capable sub-agent model);
  ///  * context exhaustion removes `read_knowledge_file` (each refused call
  ///    costs a full-window request) but keeps `delegate` — the sub-agent
  ///    researches in its own fresh context, so running out of room here is
  ///    exactly when delegation is most useful.
  @visibleForTesting
  static List<LLMTool> toolsetFor({
    required bool acceptsImageInput,
    required bool knowledgeMode,
    required bool editMode,
    Set<String> delegateKinds = const {},
    bool contextExhausted = false,
  }) {
    final baseTools = acceptsImageInput
        ? _tools
        : [
            for (final t in _tools)
              if (t.name != 'view_image' && t.name != 'list_reference_images') t
          ];
    final tools = [
      ...baseTools,
      if (knowledgeMode || editMode) ..._knowledgeTools,
      if (editMode) ..._knowledgeWriteTools,
      if (delegateKinds.isNotEmpty) ...[
        delegateToolFor(delegateKinds),
        ..._noteTools,
      ],
    ];
    return contextExhausted
        ? [for (final t in tools) if (t.name != 'read_knowledge_file') t]
        : tools;
  }

  /// Runs one agent turn: consumes the pending user message already appended
  /// to [session.history] and loops on tool calls until the model stops.
  ///
  /// [referenceImages] entries must contain `path` and `name`; ids exposed to
  /// the model are their 1-based positions in this list.
  ///
  /// [forceViewAllImages] (per-model setting) makes viewing every reference
  /// image a hard requirement before submit_prompt — for small local models
  /// that otherwise look at one image and stop.
  static Future<void> runTurn({
    required PromptOptimizerSession session,
    required dynamic modelIdentifier,
    String? systemPrompt,
    PresetOutputKind outputKind = PresetOutputKind.prompt,
    required List<Map<String, String>> referenceImages,
    bool forceViewAllImages = false,
    bool acceptsImageInput = true,
    String? knowledgeRoot,
    String? knowledgeEntryContent,
    String? contextId,
    int? contextWindow,
    double contextRatio = defaultContextRatio,
    bool kbSubAgentEnabled = false,
    dynamic kbSubAgentModelIdentifier,
    int? kbSubAgentContextWindow,
    bool kbSubAgentAcceptsImages = true,
    void Function(String message)? onLog,
    bool Function()? isCancelled,
  }) async {
    session._setRunning(true);
    final knowledgeMode = session.usesKnowledgeBase;
    // In knowledgeBase mode a pending distill request escalates
    // canWriteKnowledge for exactly as long as the request is the latest real
    // user turn — so editMode (toolset, turn budget, the write gate) follows
    // automatically; only the system prompt needs the explicit flag.
    final editMode = session.canWriteKnowledge;
    final distillTurn = knowledgeMode && session.hasPendingKbDistill;
    if (knowledgeMode && (knowledgeRoot == null || knowledgeEntryContent == null)) {
      session._setRunning(false);
      throw StateError('Knowledge mode requires knowledgeRoot and knowledgeEntryContent.');
    }
    // A text-only model must not be offered the image tools: an `image_url`
    // part sent anyway is either a 400 or — worse — silently dropped, and the
    // model answers as if it had seen the image. The reference list stays in
    // the session (and its persistence) for the UI; the model just never
    // hears about it.
    if (!acceptsImageInput && referenceImages.isNotEmpty) {
      onLog?.call('This model does not accept image input — '
          '${referenceImages.length} reference image(s) will not be offered to it.');
    }
    final effectiveRefs =
        acceptsImageInput ? referenceImages : const <Map<String, String>>[];
    final effectiveForceView = forceViewAllImages && acceptsImageInput;
    // Each delegate kind has its own precondition (playbook: enabled is not
    // available): knowledge needs a knowledge session; draft needs reference
    // images to draft from and a sub-agent model that can see them.
    final delegateKinds = <String>{
      if (kbSubAgentEnabled && knowledgeMode) 'knowledge',
      if (kbSubAgentEnabled &&
          effectiveRefs.isNotEmpty &&
          kbSubAgentAcceptsImages)
        'draft',
    };
    // Weak local models tend to issue a single tool call per turn, so viewing
    // every reference image one by one needs list + N views + submit turns.
    // Knowledge mode needs extra headroom for file listing/reading rounds.
    // Edit mode needs more still — not because writes are expensive, but
    // because the read-before-write rail forces a read round per file touched.
    final baseTurns = editMode ? 24 : (knowledgeMode ? 20 : _maxTurns);
    final minTurns = effectiveRefs.length + (knowledgeMode ? 8 : 4);
    final maxTurns = baseTurns > minTurns ? baseTurns : minTurns;
    final repo = AssistantSessionRepository();

    /// Set once a read finds no room left, for the rest of this turn.
    bool contextExhausted = false;

    /// Consecutive replies cut at the output limit while carrying tool calls.
    /// Reset by any reply that was not cut; see [maxTruncatedRounds].
    var truncatedRounds = 0;

    // Built once: it is identical on every request of this turn, and both the
    // budget check and the request itself must see the same string — it is the
    // largest fixed cost in the window (the knowledge-base file map lives in
    // it) and is re-sent in full every single request.
    final systemPromptText = _systemPromptFor(
      distillTurn: distillTurn,
      editMode: editMode,
      knowledgeMode: knowledgeMode,
      knowledgeEntryContent: knowledgeEntryContent,
      systemPrompt: systemPrompt,
      outputKind: outputKind,
      refCount: effectiveRefs.length,
      forceView: effectiveForceView,
    );
    _warnIfSystemPromptCrowds(session, systemPromptText,
        knowledgeMode: knowledgeMode, contextWindow: contextWindow, onLog: onLog);

    try {
      if (!await _prepareTurn(
        session,
        referenceImages,
        repo,
        modelIdentifier: modelIdentifier,
        systemPromptText: systemPromptText,
        contextId: contextId,
        contextWindow: contextWindow,
        contextRatio: contextRatio,
        onLog: onLog,
        isCancelled: isCancelled,
      )) {
        return;
      }
      for (int turn = 0; turn < maxTurns; turn++) {
        if (isCancelled?.call() ?? false) return;

        // Once there is no room to read, stop offering the tool at all. Left in
        // the list the model would keep calling it and keep being refused, and
        // each refusal costs another full-window request — the loop still has
        // its remaining iterations to burn. Without it the model can only
        // answer, submit or delegate (the sub-agent researches in its own
        // fresh context, so it stays useful exactly when this one is full).
        //
        // The final round offers nothing at all (standard 07 §3.8): a model
        // still working must write its answer down rather than spend the
        // last request on one more call and end the turn with nothing said.
        final finalRound = turn == maxTurns - 1;
        final activeTools = finalRound
            ? const <LLMTool>[]
            : toolsetFor(
                acceptsImageInput: acceptsImageInput,
                knowledgeMode: knowledgeMode,
                editMode: editMode,
                delegateKinds: delegateKinds,
                contextExhausted: contextExhausted,
              );

        // What this request actually offers. Dispatch is gated on it below.
        final offered = {for (final t in activeTools) t.name};

        final trimmedHistory =
            _trimForSend(session.history, keepCurrentTurnImages: effectiveForceView);
        // knowledgeEntryContent is captured once per task, but staging means no
        // edit can reach disk mid-turn, so the injected file map cannot go
        // stale within a turn.
        final outgoing = [
          ...trimmedHistory,
          if (finalRound) LLMMessage(role: LLMRole.user, content: _finalRoundNudge),
        ];
        final sentChars = occupiedChars(systemPromptText, outgoing);

        // The two fixed costs of *this* request, for the usage readout. Here
        // rather than once per turn: activeTools shrinks when the window runs
        // out, and this is the last point before the request where what is
        // actually being sent is known.
        session.recordRequestBasis(
          systemPromptChars: systemPromptText.length,
          toolSchemaChars: toolSchemaChars(activeTools),
        );

        final LLMResponse response;
        try {
          response = await _request(
            modelIdentifier: modelIdentifier,
            messages: [
              LLMMessage(role: LLMRole.system, content: systemPromptText),
              ...outgoing,
            ],
            tools: finalRound ? null : activeTools,
            contextId: contextId,
            options: {
              // Transient relay/proxy disconnects (e.g. errno 10054) should
              // not kill the whole agent turn — retry a couple of times.
              'retryCount': 2,
              // A submit_prompt is a 6-7 K-token document, measured. Only ④
              // sends a cap, so without this the deadline for ① and ③ is
              // sized against a 4096 guess that is roughly half the real
              // answer. Changes no payload — see [expectedOutputTokensKey].
              expectedOutputTokensKey: 8192,
              // A request that continues after tool results may come back
              // with nothing in it: once submit_prompt has staged the
              // deliverable, GPT-5.x ends the turn with an empty `stop`,
              // which ① otherwise fails as a broken reply — and the user saw
              // "request failed" under a prompt that had just been delivered.
              // A turn opening on the user's message (or the final-round
              // nudge) keeps the failure: an empty answer there is one.
              if (outgoing.last.role == LLMRole.tool) emptyReplyEndsTurnKey: true,
            },
            // Streamed where the route can carry tool calls over it (④
            // today), and silently downgraded everywhere else. Not for
            // incremental display — nothing here consumes a partial batch —
            // but because the streaming guard resets on every chunk while
            // the non-streaming one has to cover the whole generation. A
            // submit_prompt runs 6–7 K tokens, which is what used to time
            // out mid-write every single time
            // (docs/plans/2026-08-assistant-timeout.md).
            useStream: true,
            // Without this the turn kept going after the user pressed stop:
            // the retry loop re-sent the request (retryCount is 2 above), and
            // the stream ran to completion because nothing was watching. The
            // only cancellation checkpoints were between turns and between
            // tool calls, which is the wrong grain — a single turn is one long
            // request and almost all of the waiting happens inside it.
            isCancelled: isCancelled,
            onToolArgumentChars: (chars) =>
                session.streamingToolArgumentChars.value = chars,
          );
        } on LLMCancelled {
          // The user pressed stop. Not a failure, so no error card: being
          // told "Request cancelled by the caller" after pressing cancel is
          // noise. Nothing from this turn reaches history — the assistant
          // message is written below this block, never above it.
          return;
        } catch (e) {
          session._addEntry(OptimizerChatEntry(
            kind: OptimizerEntryKind.error,
            text: e.toString(),
          ));
          rethrow;
        } finally {
          // Whatever the request ended in, the count describes a call that is
          // no longer streaming — the next step's row starts from nothing.
          session.streamingToolArgumentChars.value = null;
        }

        // The race the hook alone cannot close: the reply may have arrived
        // complete a moment before stop was pressed, and everything below
        // writes it into the conversation and shows it. "I pressed stop and
        // it answered anyway" is the same bug whether the answer was
        // generated after the press or merely delivered after it.
        if (isCancelled?.call() ?? false) return;

        // Calibrate against what this request actually cost. Providers may
        // report no usage at all, in which case observedCharsPerToken stays as
        // it was and the conservative default keeps applying.
        final observed = ContextBudget.calibrate(
          charsSent: sentChars,
          promptTokens: LLMService.promptTokensOf(response.metadata),
        );
        if (observed != null) session.observedCharsPerToken = observed;

        // A truncated reply is not "the model ignoring instructions": a
        // submit_prompt cut mid-JSON parses as empty arguments, and executing
        // it burned a retry round on "prompt must not be empty" — after which
        // the model re-did the whole analysis and was cut in the same place.
        // Say what happened (streaming.md §2), and below, act on it.
        final truncated = response.metadata['finish_reason'] == 'length';
        final emittedTokens = truncated ? LLMService.outputTokensOf(response.metadata) : 0;
        if (truncated) {
          onLog?.call('The reply hit the model\'s output-token limit'
              '${emittedTokens > 0 ? ' after $emittedTokens tokens' : ''} and '
              'was cut off'
              '${response.toolCalls.isNotEmpty ? ' — none of its tool calls will run' : ''}.');
        }

        if (response.toolCalls.isEmpty) {
          // Model is done: plain text is a chat reply (comment, clarifying
          // question, ...), never the deliverable itself.
          final text = response.text.trim();
          // Cut with nothing in it — thinking spent the whole cap before a
          // word of answer (③ with a small maxOutputTokens does exactly
          // this). Nothing to show, so it counts like a cut call: one
          // retry, then the card that names the setting.
          if (text.isEmpty && truncated) {
            truncatedRounds++;
            if (truncatedRounds >= maxTruncatedRounds) {
              session._addEntry(OptimizerChatEntry(
                kind: OptimizerEntryKind.error,
                text: truncationStopNoticeToken,
                modelDbId: modelIdentifier is int ? modelIdentifier : null,
              ));
              return;
            }
            continue;
          }
          // Under an analysis preset the reply that closes the turn is what
          // the turn was for (`A3e`). Not the last round's: that one is the
          // status report [_finalRoundNudge] asks for, not an answer.
          final deliverable = !knowledgeMode &&
              outputKind == PresetOutputKind.analysis &&
              !finalRound;
          if (text.isNotEmpty) {
            // No echo obligation without tool calls (the payload builder only
            // replays reasoning on tool-call-bearing messages), but keep the
            // record so persistence reflects what the model actually did.
            session.history.add(LLMMessage(
              role: LLMRole.assistant,
              content: text,
              reasoningContent: response.reasoningContent,
              reasoningFieldName: response.reasoningFieldName,
              reasoningSignature: response.reasoningSignature,
              rawThinkingBlocks: response.rawThinkingBlocks,
              rawThinkingModelId: response.rawThinkingModelId,
              rawContentBlocks: response.rawContentBlocks,
              rawModelParts: response.rawModelParts,
              rawResponseItems: response.rawResponseItems,
              truncated: truncated,
              deliverable: deliverable,
              modelDbId: modelIdentifier is int ? modelIdentifier : null,
            ));
            // A cut chat reply stays a chat reply — it is what the model
            // said — but the line says where it stopped and why.
            session._addEntry(OptimizerChatEntry(
              kind: OptimizerEntryKind.assistant,
              text: text,
              truncated: truncated,
              deliverable: deliverable,
              modelDbId: modelIdentifier is int ? modelIdentifier : null,
            ));
          }
          return;
        }

        // Echo the assistant turn (with its tool calls) back into history.
        // The reasoning rides along: DeepSeek-style endpoints reject the next
        // request with 400 when a tool-calling turn's reasoning_content is not
        // replayed (reasoning.md §3), and _prepareChatPayload echoes it from
        // these fields under its original name.
        session.history.add(LLMMessage(
          role: LLMRole.assistant,
          content: response.text,
          reasoningContent: response.reasoningContent,
          reasoningFieldName: response.reasoningFieldName,
          reasoningSignature: response.reasoningSignature,
          rawThinkingBlocks: response.rawThinkingBlocks,
          rawThinkingModelId: response.rawThinkingModelId,
          rawContentBlocks: response.rawContentBlocks,
          rawModelParts: response.rawModelParts,
          rawResponseItems: response.rawResponseItems,
          toolCalls: response.toolCalls,
          truncated: truncated,
          modelDbId: modelIdentifier is int ? modelIdentifier : null,
        ));
        if (response.text.trim().isNotEmpty) {
          // Narration beside the calls: a cut one ends mid-sentence, and
          // says so like a text-only reply would.
          session._addEntry(OptimizerChatEntry(
            kind: OptimizerEntryKind.assistant,
            text: response.text.trim(),
            truncated: truncated,
            modelDbId: modelIdentifier is int ? modelIdentifier : null,
          ));
        }

        // A reply cut mid-call runs none of its calls: half a JSON argument
        // is not an argument. Every call is still paired — the history must
        // stay sendable — with a result that says what to do instead. One
        // cut earns the directed retry; a second in a row ends the turn,
        // because at that point the cap is the problem and only the user can
        // raise it. Ahead of `offered` and every executor, so a cut
        // write_knowledge_file never stages half a file.
        if (truncated) {
          truncatedRounds++;
          for (final call in response.toolCalls) {
            session.history.add(LLMMessage(
              role: LLMRole.tool,
              content: jsonEncode(truncatedToolResult(
                  emittedTokens: emittedTokens > 0 ? emittedTokens : null)),
              toolCallId: call.id,
              toolName: call.name,
            ));
          }
          if (truncatedRounds >= maxTruncatedRounds) {
            onLog?.call('Two consecutive replies were cut at the output limit '
                '— stopping this turn. Raise the model\'s max output in its '
                'settings.');
            session._addEntry(OptimizerChatEntry(
              kind: OptimizerEntryKind.error,
              text: truncationStopNoticeToken,
              modelDbId: modelIdentifier is int ? modelIdentifier : null,
            ));
            return;
          }
          continue;
        }
        truncatedRounds = 0;

        // Images requested this turn; attached after all tool results so the
        // history stays valid for providers whose tool results are text-only.
        final pendingViews = <Map<String, String>>[];

        // Every tool call in the batch MUST get a paired tool result before
        // this method returns: the assistant message (with its toolCalls) is
        // already in history, and the finally block persists whatever is
        // there. An unpaired tool call would poison the session — both
        // OpenAI-compatible and Gemini endpoints reject such a history — so
        // on cancellation the remaining calls get a synthetic "cancelled"
        // result, and a throwing tool becomes an error result instead of
        // escaping the loop.
        //
        // The ONE deliberate exception is a valid, solo ask_user call: it
        // stays dangling and the turn returns, because its result IS the
        // user's answer. This is safe — nothing sends the history while it
        // dangles (the turn has ended), every path back into a turn pairs it
        // first (answerAskUser, resolvePendingAskUserAsFreeText, or the
        // self-healing guard at the top of runTurn), and canStageAskUser
        // keeps the dangling call the LAST message so that pairing lands
        // inside its own batch.
        var cancelledMidBatch = false;
        String? pendingAskCallId;
        for (final call in response.toolCalls) {
          Map<String, dynamic> result;
          if (cancelledMidBatch || (isCancelled?.call() ?? false)) {
            cancelledMidBatch = true;
            result = {
              'status': 'cancelled',
              'message': 'The user cancelled the task before this tool ran.',
            };
          } else {
            final dispatched = await _dispatchToolCall(
              call,
              response.toolCalls,
              session,
              offered: offered,
              modelIdentifier: modelIdentifier,
              kbSubAgentModelIdentifier: kbSubAgentModelIdentifier,
              kbSubAgentContextWindow: kbSubAgentContextWindow,
              knowledgeRoot: knowledgeRoot,
              delegateKinds: delegateKinds,
              referenceImages: effectiveRefs,
              pendingViews: pendingViews,
              forceView: effectiveForceView,
              systemPromptText: systemPromptText,
              contextWindow: contextWindow,
              contextId: contextId,
              onLog: onLog,
              isCancelled: isCancelled,
              onContextExhausted: () => contextExhausted = true,
            );
            if (dispatched == null) {
              pendingAskCallId = call.id;
              continue; // Deliberately NO paired result — see comment above.
            }
            result = dispatched;
          }
          session.history.add(LLMMessage(
            role: LLMRole.tool,
            content: jsonEncode(result),
            toolCallId: call.id,
            toolName: call.name,
          ));
        }

        for (final view in pendingViews) {
          session.history.add(LLMMessage(
            role: LLMRole.user,
            content: '$viewResultMarker Reference image #${view['id']} (${view['name']}) is attached.',
            attachments: [
              LLMAttachment.fromFile(
                File(view['path']!),
                _mimeTypeFor(view['path']!),
                referenceType: LLMReferenceType.viewOnly,
              ),
            ],
          ));
        }

        // Stop only after the batch is fully paired and executed views are
        // attached, so the persisted history stays valid for the next turn.
        if (cancelledMidBatch) return;
        // A staged question ends the turn: the model asked, now the user
        // answers. The resumed turn (after answerAskUser or a free-text
        // reply) gets a fresh maxTurns budget.
        if (pendingAskCallId != null) return;
      }
      // Only reachable when even the tools-free final round came back with tool
      // calls: those were paired as not offered, so the history is valid, but
      // the user got no answer and has to be told why rather than left
      // watching the turn simply stop.
      onLog?.call('Reached the maximum of $maxTurns agent turns — stopping.');
      session._addEntry(OptimizerChatEntry(
        kind: OptimizerEntryKind.notice,
        text: roundLimitNoticeToken,
      ));
    } finally {
      // Persist whatever this turn produced, even on error/cancel.
      try {
        await _syncPersistence(session, referenceImages, repo);
      } catch (e) {
        onLog?.call('Session persistence failed: $e');
      }
      session._setRunning(false);
    }
  }

  /// Upserts the session row (title derived from the first user message) and
  /// appends any not-yet-persisted history messages, then applies the
  /// retention policy.
  static Future<void> _syncPersistence(
    PromptOptimizerSession session,
    List<Map<String, String>> referenceImages,
    AssistantSessionRepository repo,
  ) async {
    if (session.history.isEmpty) return;
    session.title ??= _deriveTitle(session.history);
    await repo.upsertSession(
      id: session.id,
      title: session.title,
      mode: session.mode,
      refImages: referenceImages,
    );
    if (session.history.length > session.persistedCount) {
      final startSeq = await repo.nextSeq(session.id);
      await repo.appendMessages(
          session.id, startSeq, session.history.sublist(session.persistedCount));
      session.persistedCount = session.history.length;
    }
    final keepStr = await DatabaseService().getSetting(retentionSettingKey);
    await repo.enforceRetention(int.tryParse(keepStr ?? '') ?? defaultRetention);
  }

  static String _deriveTitle(List<LLMMessage> history) {
    final first = history
        .where(_isRealUserTurn)
        .map((m) => m.content.trim())
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');
    final oneLine = first.replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length <= 40 ? oneLine : '${oneLine.substring(0, 40)}…';
  }

  /// The knowledge files the current answer rests on, in the order the agent
  /// consulted them.
  ///
  /// The window is the live one — from [_recentBoundary] — rather than
  /// strictly "this turn". A template read three turns ago and still being
  /// sent with every request *is* something the answer is grounded in, and a
  /// list that dropped it the moment the model stopped re-requesting it would
  /// shrink as the conversation went on, for no reason the user could see.
  /// Once layer 1 elides that read it genuinely has left the request, and it
  /// correctly leaves this list with it.
  ///
  /// Scans tool **results**, like every other "what has been read" question in
  /// this file — see the invariant documented on [_liveReadPages]. A failed
  /// read carries neither content nor a path, so it cannot appear here.
  static List<String> citedKnowledgeFiles(PromptOptimizerSession session) {
    final history = session.history;
    final paths = <String>{};

    for (int i = _recentBoundary(history); i < history.length; i++) {
      final m = history[i];
      if (m.role != LLMRole.tool || m.toolName != 'read_knowledge_file') continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(m.content);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;
      final path = decoded['path'];
      if (path is String && path.isNotEmpty) paths.add(path);
    }

    // Insertion-ordered, so the list reads in the order the agent worked.
    return paths.toList();
  }

  /// Staged knowledge edits still waiting on the user, oldest first.
  ///
  /// Read off the transcript rather than tracked in a list of its own: the
  /// transcript is where an edit's state actually lives, and a parallel list
  /// would be one more thing that can disagree with the card on screen about
  /// whether something has already been written.
  static List<OptimizerChatEntry> pendingKbEdits(PromptOptimizerSession session) => [
        for (final e in session.transcript)
          if (e.kind == OptimizerEntryKind.kbEdit && e.editState == KbEditState.pending) e,
      ];

  /// How many tool steps the turn now running has taken.
  ///
  /// Counted from the last user turn rather than over the whole transcript, so
  /// the header's "step N" restarts with each question instead of climbing for
  /// the life of the conversation. Read off the transcript, not the history,
  /// because it answers a question about what is drawn on screen.
  ///
  /// `10i` writes this as `步骤 8 / 10`. There is no total here and there
  /// cannot be one — the agent decides how many tools to call as it goes — so
  /// the header reports the count alone.
  static int currentTurnSteps(PromptOptimizerSession session) {
    int steps = 0;
    final transcript = session.transcript;
    for (int i = transcript.length - 1; i >= 0; i--) {
      final kind = transcript[i].kind;
      if (kind == OptimizerEntryKind.user) break;
      if (kind == OptimizerEntryKind.tool) steps++;
    }
    return steps;
  }

  /// Chars in what a request actually carries: the system prompt (which is
  /// rebuilt and re-sent every turn, knowledge-base file map and all), message
  /// text, tool-call arguments, and a stand-in for attachments.
  ///
  /// Tool-call arguments are counted because they are not small: a staged
  /// write_knowledge_file or submit_prompt puts a whole file body in the
  /// assistant message, which a content-only tally misses entirely.
  ///
  /// This is also the number [ContextBudget.calibrate] divides into the
  /// provider's reported token count, so it has to measure the same request the
  /// provider billed — hence system prompt included, not history alone.
  static int occupiedChars(String systemPrompt, List<LLMMessage> messages) {
    int total = systemPrompt.length;
    for (final m in messages) {
      total += m.content.length;
      // Replayed on tool-call turns (see _prepareChatPayload), so it is part
      // of what the provider bills.
      total += m.reasoningContent?.length ?? 0;
      total += m.attachments.length * _attachmentChars;
      for (final call in m.toolCalls) {
        total += call.name.length;
        for (final entry in call.arguments.entries) {
          total += entry.key.length + entry.value.toString().length;
        }
      }
    }
    return total;
  }

  /// Chars the tool schemas add to every request.
  ///
  /// Not part of [occupiedChars] and deliberately kept out of it: that number
  /// is the budget basis *and* [ContextBudget.calibrate]'s divisor, and both
  /// were tuned against a tally that excludes tools. Widening it would move the
  /// compaction trigger for every existing session. So tools are measured
  /// separately, for display only — the readout is allowed to be more complete
  /// than the budget, and saying so is better than a bar with a missing slice.
  ///
  /// The count is of the JSON that goes on the wire: every protocol serializes
  /// name, description and parameter schema, whatever wrapper it puts them in.
  static int toolSchemaChars(List<LLMTool> tools) {
    int total = 0;
    for (final t in tools) {
      total += t.name.length + t.description.length;
      total += jsonEncode(t.parameters).length;
    }
    return total;
  }

  /// What this session currently spends of the model's context window, split
  /// the way the request is.
  ///
  /// Derived on every call rather than cached, for the same reason the read cap
  /// is recomputed per tool call: a cached figure has to be invalidated by
  /// eliding, compaction and every appended tool result, and the one thing this
  /// subsystem has repeatedly proven is that nothing remembers to do that (see
  /// assistant-context.md, *Rejected*). The walk is over message lengths, not
  /// their contents, so it is cheap enough to run per rebuild.
  ///
  /// [contextWindowTokens] is the model's configured window straight out of
  /// `llm_models.context_window` — the same nullable tri-state the turn is
  /// budgeted with, decoded here by [ContextBudget.modeOf] and nowhere else.
  ///
  /// History is measured **after** [_trimForSend], because that is what will be
  /// sent; the untrimmed history would over-report by every elided knowledge
  /// read the session has ever done.
  static ContextUsageSnapshot measureContext(
    PromptOptimizerSession session, {
    required int? contextWindowTokens,
  }) {
    // Nothing has gone out and nothing has been said: report "not measured"
    // rather than a confident zero for a system prompt that simply has not been
    // built yet.
    if (session.systemPromptChars == 0 && session.history.isEmpty) {
      return ContextUsageSnapshot.placeholder;
    }

    final perToken = session.observedCharsPerToken ?? ContextBudget.charsPerToken;
    final (int windowChars, ContextWindowBasis basis) =
        switch (ContextBudget.modeOf(contextWindowTokens)) {
      ContextWindowMode.specified => (
          (contextWindowTokens! * perToken).round(),
          ContextWindowBasis.configured,
        ),
      ContextWindowMode.unset => (
          (ContextBudget.defaultWindowTokens * perToken).round(),
          ContextWindowBasis.assumed,
        ),
      ContextWindowMode.unlimited => (0, ContextWindowBasis.unlimited),
    };

    return ContextUsageSnapshot(
      windowChars: windowChars,
      charsPerToken: perToken,
      basis: basis,
      slices: {
        // Omitted rather than zeroed while unmeasured: a session restored from
        // the database has its whole history back and no idea what system
        // prompt the next turn will build, and "0" there would read as a free
        // one. The next request fills both in.
        if (session.systemPromptChars > 0)
          ContextUsageSlice.systemPrompt: session.systemPromptChars,
        if (session.toolSchemaChars > 0) ContextUsageSlice.tools: session.toolSchemaChars,
        // occupiedChars('') is the history's own share — the system prompt is
        // already its own slice above, and double-counting it would push the
        // bar past the window it is drawn in.
        ContextUsageSlice.history: occupiedChars('', _trimForSend(session.history)),
      },
    );
  }

  @visibleForTesting
  static Set<int> liveReadPagesForTest(PromptOptimizerSession session, String relPath) =>
      _liveReadPages(session, relPath);

  @visibleForTesting
  static Set<String> liveViewedPathsForTest(PromptOptimizerSession session,
          {bool keepCurrentTurnImages = false}) =>
      _liveViewedPaths(session, keepCurrentTurnImages: keepCurrentTurnImages);

  /// The outgoing copy of a whole history, windows applied.
  ///
  /// Exposed because the property worth pinning is not either window on its
  /// own but the agreement between them: what [_trimForSend] still carries
  /// must be exactly what [_liveViewedPaths] reports as live.
  @visibleForTesting
  static List<LLMMessage> trimForSendForTest(List<LLMMessage> history,
          {bool keepCurrentTurnImages = false}) =>
      _trimForSend(history, keepCurrentTurnImages: keepCurrentTurnImages);

  @visibleForTesting
  static LLMMessage elideForTest(LLMMessage m,
          {bool bulk = true, bool attachments = true}) =>
      _elide(m, bulk: bulk, attachments: attachments);

  /// The sub-agent's task message. Two shapes, not one template with an
  /// empty slot: a brief without paths must not contain a "start from"
  /// section at all — a heading over nothing reads as an instruction to go
  /// find those (nonexistent) sources.
  @visibleForTesting
  static String buildDelegateTask(String task, List<String> paths) {
    if (paths.isEmpty) return task;
    return '$task\n\nStart from these knowledge-base files:\n'
        '${paths.map((p) => '- $p').join('\n')}';
  }

  /// Writes a staged edit to disk after the user approved it, and flips the
  /// transcript card to its terminal state. This is the only path that mutates
  /// the knowledge base — the agent never writes directly.
  ///
  /// Throws [KbEditConflictException] — card marked failed, nothing written —
  /// when the file on disk no longer matches the content the edit was proposed
  /// against.
  static Future<void> applyStagedKbEdit({
    required PromptOptimizerSession session,
    required String editId,
  }) async {
    final entry = session._findKbEdit(editId);
    if (entry == null || entry.editState != KbEditState.pending) return;
    final relPath = entry.targetPath!;
    try {
      final kb = KnowledgeBaseService();
      // The root the edit was staged against, not whatever Settings says now:
      // a card can wait a long time, and the folder can be switched meanwhile.
      final root = entry.knowledgeRoot ?? await kb.getRoot();
      if (root == null) throw KbPathException('The knowledge base folder is not configured.');
      // Re-verify against disk (standard 08 §3.6). The card previews a diff
      // from oldContent; if the file no longer holds that — a hand edit while
      // the card waited, or another card for the same file applied first —
      // writing would silently discard changes nobody reviewed. A create
      // (oldContent == null) conflicts with a file that appeared meanwhile.
      if (kb.readFullFile(root, relPath) != entry.oldContent) {
        throw KbEditConflictException(relPath);
      }
      // Before the write, not after: the point of the copy is the content that
      // is about to stop existing (standard 08 §3.2 — a failed backup fails the
      // write). Forced when the write skips confirmation: nobody read it before
      // it landed. Only a file's first write of the session is backed up, so
      // the .bak holds the user's own version rather than being rewritten to
      // the agent's previous draft on every edit. A create has nothing to copy.
      final policy = session.writePolicy;
      final backupKey = '$root|$relPath';
      if ((policy.backupBeforeOverwrite || !policy.confirmEachWrite) &&
          entry.oldContent != null &&
          !session._backedUpPaths.contains(backupKey)) {
        await kb.backupFile(root, relPath);
        session._backedUpPaths.add(backupKey);
      }
      await kb.writeFile(root, relPath, entry.newContent!);
      // The file changed, so every read of it recorded so far describes content
      // that no longer exists — and page boundaries move on a rewrite, so
      // invalidating single pages would be meaningless. Marking the point in
      // history rather than dropping a flag keeps the re-read that follows
      // able to satisfy the read-before-write rail again.
      session.knowledgeStaleAt[relPath] =
          session.history.isEmpty ? null : session.history.last;
      session._resolveKbEdit(editId, KbEditState.applied);
    } catch (e) {
      session._resolveKbEdit(editId, KbEditState.failed, error: '$e');
      rethrow;
    }
  }

  /// Discards a staged edit. The read cache is deliberately left alone — the
  /// file on disk never changed.
  static void rejectStagedKbEdit({
    required PromptOptimizerSession session,
    required String editId,
  }) {
    final entry = session._findKbEdit(editId);
    if (entry == null || entry.editState != KbEditState.pending) return;
    session._resolveKbEdit(editId, KbEditState.rejected);
  }

  /// Whether an `ask_user` call may be staged — left deliberately unpaired so
  /// the turn can suspend on it (invariant 8).
  ///
  /// Only when it is the message's **only** tool call. Suspending is safe
  /// precisely because the dangling call is then the last thing in the
  /// history: the result appended when the user answers lands immediately
  /// after the assistant message that made it. Batched with anything else that
  /// runs, that stops being true — `view_image` appends the image as a *user*
  /// message once the batch finishes, so the answer would arrive behind it and
  /// the history would read `assistant(tool_calls) → tool → user → tool`.
  /// Providers reject that ("an assistant message with 'tool_calls' must be
  /// followed by tool messages responding to each tool_call_id",
  /// docs/api/tools.md §3), and because history is cumulative the request
  /// never becomes valid again — the session is dead, not just the turn.
  ///
  /// The tool's own description already tells the model to ask alone; this is
  /// the rail that makes it structural rather than advisory. A batched
  /// question is refused with an error result, so the model simply re-asks on
  /// the next iteration of the same turn.
  @visibleForTesting
  static bool canStageAskUser(List<LLMToolCall> batch) => batch.length == 1;

  /// Content of the stub result [repairToolCallPairing] gives a call whose
  /// real result is missing.
  static const String notRunStubMessage =
      '[not run] No result was recorded for this tool call — treat it as not executed.';

  /// Makes [history] pairable again (standard 07 §3.2, 10 §4.3).
  ///
  /// Returns a new list; retained messages are the same objects. Rules:
  ///  * a call with no result in the contiguous tool run after its assistant
  ///    message gets a `[not run]` stub at the end of that run, so the batch
  ///    stays one block;
  ///  * a tool message outside such a run, answering no call of its batch, or
  ///    answering one twice, is dropped;
  ///  * calls with an empty id cannot be answered and are stripped; an
  ///    assistant message left with neither text nor calls is dropped.
  ///
  /// The one call left dangling on purpose is a valid `ask_user` at the very
  /// end of the history — the suspended question of invariant 8, which
  /// [pendingAskUser] derives and the next turn pairs.
  static List<LLMMessage> repairToolCallPairing(List<LLMMessage> history) =>
      [for (final e in _repairPairingWithOrigins(history)) e.message];

  @visibleForTesting
  static void cancelDanglingAskUserForTest(PromptOptimizerSession session) =>
      _cancelDanglingAskUser(session);

  /// Pairs the pending ask_user call with the user's structured answers and
  /// flips the card. Does NOT run the model — the caller re-enqueues a
  /// promptRefine task. No-ops when [callId] is not the pending call (same
  /// idempotence contract as [rejectStagedKbEdit]).
  static void answerAskUser({
    required PromptOptimizerSession session,
    required String callId,
    required List<AskUserAnswer> answers,
  }) {
    if (session.pendingAskUser?.callId != callId) return;
    final payload = [for (final a in answers) a.toJson()];
    _pairDanglingAskUser(
      session,
      callId,
      {'status': 'ok', 'answers': payload},
      // Only reachable for a pre-rail history (see _pairDanglingAskUser): the
      // choices still have to reach the model, just in the user role.
      fallback: 'Answers to the questions you asked: ${jsonEncode(payload)}',
    );
    session._resolveAskUser(callId, AskUserState.answered, answers: answers);
  }

  /// Pairs the pending ask_user call with a "user answered in free text"
  /// note. Called by the send path before appending the user turn, so typing
  /// into the normal input box always works as an escape hatch while a
  /// question is pending.
  static void resolvePendingAskUserAsFreeText({
    required PromptOptimizerSession session,
    required String callId,
  }) {
    if (session.pendingAskUser?.callId != callId) return;
    // No fallback message: the user's free text is appended as its own user
    // turn by the caller, right after this.
    _pairDanglingAskUser(session, callId, {
      'status': 'ok',
      'note': 'The user replied in free text instead of choosing options — '
          'see the user message that follows.',
    });
    session._resolveAskUser(callId, AskUserState.dismissed);
  }

}
