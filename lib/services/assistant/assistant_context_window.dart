part of 'prompt_optimizer_agent.dart';

/// Share of the window above which the system prompt is called out.
///
/// Past half, a two-message conversation cannot fit — and unlike history, the
/// system prompt is re-sent in full every request and compaction cannot touch
/// it, so nothing downstream can rescue it.
const double _systemPromptWarnShare = 0.5;

/// Memory management: the most recent user turns whose tool results are
/// never elided or compacted away.
const int _keepRecentTurns = 6;

/// The same window, for **image attachments only**, which are far heavier
/// than anything else it protects.
///
/// A knowledge read costs its characters once. An attachment costs a
/// re-upload and a fresh image-token bill on *every request of every turn*
/// it survives into — a dozen or more times per turn in an agent loop.
/// Six turns of that is what made one session upload 55 MB
/// (docs/plans/2026-08-assistant-timeout.md).
///
/// Eliding early is cheap precisely because it is reversible: liveness is
/// derived, not tracked, so the model may simply call `view_image` again
/// and pay for the picture in the one turn that actually needs it. Two
/// turns keeps it through the turn that viewed it and the follow-up that
/// usually refines it.
const int _keepAttachmentTurns = 2;

/// Most image attachments any one request carries (standard 07 §3.6).
///
/// The attachment window is counted in turns, and one turn can view every
/// reference image — each then re-uploaded on every later request of that
/// turn. The cap bounds the payload per request whatever a turn does; the
/// window still bounds how long any one image lingers.
const int _maxLiveImages = 3;

/// Layer-2 compaction's secondary trigger: raw message count, independent of
/// size. A long conversation of short turns costs little context but still
/// slows every request down.
const int _compactMaxMessages = 120;

/// Retention target as a share of the trigger budget: standard 10 §3.1's
/// RETAIN_TARGET / COMPACT_TRIGGER (0.45 / 0.7). The gap between the two is
/// what keeps the turn after a compaction from compacting again.
const double _retainTargetShare = 0.45 / 0.7;

/// Turns kept verbatim however far over budget the history is (10 §3.1).
const int _minKeepTurns = 2;

/// Worst-case size charged for the summary a fold will produce — 10 §3.1's
/// 1000-token summary budget, in the character domain.
final int _summaryAllowanceChars = (1000 * ContextBudget.charsPerToken).round();

/// What a knowledge read may spend right now.
///
/// Recomputed per tool call rather than once per turn, because a single
/// assistant message can carry several read_knowledge_file calls and both
/// Gemini and GPT routinely emit them that way. Reading occupancy from
/// [PromptOptimizerSession.history] makes that fall out for free: each
/// result is appended before the next call runs, so the second read already
/// sees what the first one cost. Computing it once per turn would let every
/// call in the batch claim the same remaining window.
///
/// Nothing reclaims this mid-turn — compaction only runs at a turn boundary
/// and cannot fold the current turn anyway — so the cap is the only thing
/// standing between a long tool loop and an overflowing request.
int _readCapNow(
  PromptOptimizerSession session,
  String systemPrompt,
  int? contextWindow, {
  bool keepCurrentTurnImages = false,
}) =>
    ContextBudget.readCapChars(
      contextWindow,
      PromptOptimizerAgent.occupiedChars(systemPrompt,
          _trimForSend(session.history, keepCurrentTurnImages: keepCurrentTurnImages)),
      observedCharsPerToken: session.observedCharsPerToken,
    );

/// Whether [m] is something the *user* actually said, as opposed to a
/// message the agent injects into the user role.
///
/// `view_image` results and compaction summaries both arrive as user
/// messages; counting either as a turn would split a turn in half or make
/// the protected window shorter than it claims. Shared so the two callers
/// that need this cannot drift apart.
bool _isRealUserTurn(LLMMessage m) =>
    m.role == LLMRole.user &&
    !m.content.startsWith(PromptOptimizerAgent.viewResultMarker) &&
    !m.content.startsWith(PromptOptimizerAgent.summaryMarker) &&
    !m.content.startsWith(PromptOptimizerAgent.kbEditOutcomesMarker);

/// Whether [m] is the result [PromptOptimizerAgent.resolvePendingAskUserAsFreeText] pairs a
/// question with: an `ask_user` result with status ok and no structured
/// answers. The user message right after it continues the asking turn.
///
/// A structured answer (`answers` present) is excluded on purpose — that
/// path resumes with no user message at all, so a user turn after it is a
/// new request.
bool _isFreeTextAskUserReply(LLMMessage m) {
  if (m.role != LLMRole.tool || m.toolName != 'ask_user') return false;
  try {
    final decoded = jsonDecode(m.content);
    return decoded is Map && decoded['status'] == 'ok' && decoded['answers'] == null;
  } catch (_) {
    return false;
  }
}

/// Index of the user message that opens the protected "recent" window
/// (the last [_keepRecentTurns] real user turns). 0 = protect everything.
int _recentBoundary(List<LLMMessage> history) =>
    _boundaryOf(history, _keepRecentTurns);

/// The same, for image attachments — a shorter window, so always at or
/// after [_recentBoundary].
///
/// **[_elide] and [_liveViewedPaths] must both use this one.** They are two
/// halves of a single rule: one decides whether the attachment is still in
/// the request, the other tells the model whether it needs to ask for it
/// again. Split them onto different boundaries and the model is refused a
/// re-view of a picture that is no longer being sent — the exact deadlock
/// assistant-context.md's "Rejected" section describes, with no way out but
/// restarting the app.
int _attachmentBoundary(List<LLMMessage> history) =>
    _boundaryOf(history, _keepAttachmentTurns);

int _boundaryOf(List<LLMMessage> history, int keepTurns) {
  int userSeen = 0;
  for (int i = history.length - 1; i >= 0; i--) {
    if (_isRealUserTurn(history[i])) {
      userSeen++;
      if (userSeen >= keepTurns) return i;
    }
  }
  return 0;
}

/// Below this many chars a read is not worth doing: the model would get a
/// fragment too small to reason from, and would likely just ask for the next
/// one, burning a full-window request each time.
const int _minReadChars = 2000;

/// Rough per-attachment char cost, standing in for an image's token price.
///
/// An image carries no characters but is far from free, so this stand-in
/// *is* the measurement — counting it as zero (as the pre-3.5 threshold
/// did) makes a session with reference images look emptier than it is and
/// over-grants the knowledge read budget by exactly that much.
///
/// 2200 tokens × [ContextBudget.charsPerToken]. The old 2000 chars was
/// worth about 1300 tokens at that ratio, roughly half the real article:
/// three cosplay references in one measured session billed ~6850 image
/// tokens, ~2280 each.
///
/// A single number is defensible only because
/// [ImageCompressor.viewOnlyMaxLongEdge] now bounds the input — every
/// view-only attachment arrives at or under 1568px, which caps it near 3300
/// tokens and clusters the common case around 2200. Before that cap an
/// attachment could be any size at all and no constant meant anything.
const int _attachmentChars = 3300;

/// Pages of [relPath] whose content the model can still read in what will be
/// sent next.
///
/// Derived from the live history rather than tracked in a set. A set has to
/// be told when its content disappears, and nothing told it: [_elide]
/// replaces a read's result with a stub and [_maybeCompact] folds it into a
/// summary that drops tool results outright, yet the key survived both — so
/// the model asking to re-read was answered "already in the conversation"
/// pointing at content that no longer existed, with no way to recover. The
/// question is only ever "is it still in context", which the history answers
/// directly.
///
/// Scans tool *results*, not the assistant's tool *calls*: the assistant
/// message is appended to history before its calls execute, so matching on
/// calls would find the very read being executed and report it as cached.
/// Results also make failed reads (no `content` key) correctly not count.
Set<int> _liveReadPages(PromptOptimizerSession session, String relPath) {
  final history = session.history;
  // Reads before the recent boundary are elided by _trimForSend; reads
  // before the file was last written no longer describe what is on disk.
  final boundary = _recentBoundary(history);
  final staleAt = _staleFrom(session, relPath);
  final from = boundary > staleAt ? boundary : staleAt;
  final pages = <int>{};
  for (int i = from; i < history.length; i++) {
    final m = history[i];
    if (m.role != LLMRole.tool || m.toolName != 'read_knowledge_file') continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(m.content);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    if (decoded['path'] != relPath) continue;
    // Errors and the "already in context" note carry no content, so they are
    // not evidence the model has ever seen the file.
    if (decoded['content'] == null) continue;
    final page = decoded['page'];
    if (page is int) pages.add(page);
  }
  return pages;
}

/// First history index whose reads of [relPath] still describe the file on
/// disk — see [PromptOptimizerSession.knowledgeStaleAt].
int _staleFrom(PromptOptimizerSession session, String relPath) {
  if (!session.knowledgeStaleAt.containsKey(relPath)) return 0;
  final marker = session.knowledgeStaleAt[relPath];
  if (marker == null) return 0;
  final at = session.history.lastIndexWhere((m) => identical(m, marker));
  // Gone means compaction folded it: whatever survived came after the write.
  return at < 0 ? 0 : at + 1;
}

/// Reference-image paths whose attachment is still part of what will be sent
/// next — i.e. the synthetic `view_image` message sits inside the recent
/// window, where [_trimForSend] does not strip attachments.
///
/// Derived from the live history, exactly like [_liveReadPages], and for the
/// same reason: the previous implementation refused a re-view whenever the
/// path was in [PromptOptimizerSession.viewedImagePaths], but that set was
/// never invalidated when [_elide] dropped the attachment from the outgoing
/// copy or [_maybeCompact] folded the message away — so the model was pointed
/// at an attachment that no longer existed in the request, with no way to
/// recover (the exact deadlock assistant-context.md's "Rejected" section
/// describes for knowledge reads). [PromptOptimizerSession.viewedImagePaths]
/// remains as the UI's "has been looked at" badge only; it no longer gates
/// anything the model asks for.
Set<String> _liveViewedPaths(PromptOptimizerSession session,
    {bool keepCurrentTurnImages = false}) {
  final history = session.history;
  final paths = <String>{};
  for (final i
      in _liveAttachmentIndices(history, keepCurrentTurnImages: keepCurrentTurnImages)) {
    for (final att in history[i].attachments) {
      final path = att.path;
      if (path != null) paths.add(path);
    }
  }
  return paths;
}

/// Layer-1 (lossless in DB, per-request) trimming: before the recent
/// window, bulky knowledge-file tool results are elided and viewed-image
/// attachments dropped. User/assistant text and submit_prompt results are
/// always kept. Tool call/result pairing is preserved (only contents are
/// shortened), which Gemini requires.
List<LLMMessage> _trimForSend(List<LLMMessage> history,
    {bool keepCurrentTurnImages = false}) {
  final boundary = _recentBoundary(history);
  final liveImages =
      _liveAttachmentIndices(history, keepCurrentTurnImages: keepCurrentTurnImages);
  var anyImageDropped = false;
  for (int i = 0; i < history.length && !anyImageDropped; i++) {
    anyImageDropped = _isViewWithAttachments(history[i]) && !liveImages.contains(i);
  }
  if (boundary == 0 && !anyImageDropped) return history;
  return [
    for (int i = 0; i < history.length; i++)
      _elide(
        history[i],
        bulk: i < boundary,
        attachments: !liveImages.contains(i),
      ),
  ];
}

bool _isViewWithAttachments(LLMMessage m) =>
    m.role == LLMRole.user &&
    m.content.startsWith(PromptOptimizerAgent.viewResultMarker) &&
    m.attachments.isNotEmpty;

/// Indices of the view-result messages whose attachments are still sent:
/// inside [_attachmentBoundary] and among the newest [_maxLiveImages]
/// images.
///
/// With [keepCurrentTurnImages] — the per-model force-view-all flag, which
/// promises the model has seen every reference before `submit_prompt` —
/// the current turn's attachments are all kept. They still count toward
/// the cap, so older rounds leave first.
///
/// The one rule both [_trimForSend] and [_liveViewedPaths] read: whether an
/// attachment is still sent and whether the model may ask for it again are
/// two halves of it (invariant 4).
Set<int> _liveAttachmentIndices(List<LLMMessage> history,
    {bool keepCurrentTurnImages = false}) {
  final windowStart = _attachmentBoundary(history);
  final currentTurnStart =
      keepCurrentTurnImages ? _boundaryOf(history, 1) : history.length;
  final live = <int>{};
  var newer = 0;
  for (int i = history.length - 1; i >= windowStart; i--) {
    final m = history[i];
    if (!_isViewWithAttachments(m)) continue;
    if (i >= currentTurnStart || newer < _maxLiveImages) live.add(i);
    newer += m.attachments.length;
  }
  return live;
}

/// The outgoing copy of [m], with whichever windows it has fallen out of
/// applied. [bulk] governs knowledge/note reads and staged file bodies;
/// [attachments] governs viewed images, which leave the request sooner —
/// see [_keepAttachmentTurns].
LLMMessage _elide(
  LLMMessage m, {
  required bool bulk,
  required bool attachments,
}) {
  // read_note results elide exactly like knowledge reads: both are bulk
  // text the model pulled in on demand and can pull in again — notes even
  // more safely, since nothing ever rewrites a stored note.
  if (bulk &&
      m.role == LLMRole.tool &&
      (m.toolName == 'read_knowledge_file' || m.toolName == 'read_note') &&
      m.content.length > 300) {
    return LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({
        'status': 'ok',
        'note': 'Content elided to save context — it was read and processed earlier in this conversation.',
      }),
      toolCallId: m.toolCallId,
      toolName: m.toolName,
    );
  }
  if (attachments &&
      m.role == LLMRole.user &&
      m.content.startsWith(PromptOptimizerAgent.viewResultMarker) &&
      m.attachments.isNotEmpty) {
    return LLMMessage(
      role: LLMRole.user,
      content: '${m.content} (attachment elided to save context — it was inspected earlier.)',
    );
  }
  // A write's tool *result* is tiny, but the assistant message that requested
  // it keeps the whole proposed file body in its tool-call arguments — which
  // would otherwise be re-sent on every later request for the rest of the
  // session. The staged content was already shown to the user, so the model
  // does not need it back.
  if (bulk &&
      m.role == LLMRole.assistant &&
      m.toolCalls.any((c) =>
          c.name == 'write_knowledge_file' &&
          (c.arguments['content']?.toString().length ?? 0) > 300)) {
    return LLMMessage(
      role: LLMRole.assistant,
      content: m.content,
      // Reasoning must survive verbatim: eliding or editing it would break
      // the ① family echo-back contract the same way dropping a
      // thoughtSignature breaks Gemini's — and ④'s raw thinking blocks the
      // same way (an incomplete replay silently disables thinking).
      reasoningContent: m.reasoningContent,
      reasoningFieldName: m.reasoningFieldName,
      reasoningSignature: m.reasoningSignature,
      rawThinkingBlocks: m.rawThinkingBlocks,
      rawThinkingModelId: m.rawThinkingModelId,
      // Not carried: the verbatim copy holds the full file body inside its
      // tool_use input, which is exactly what this elision exists to keep
      // out of every later request. Without it the turn is rebuilt from
      // the elided fields below — a server-tool turn that also wrote a
      // large file loses its search blocks on replay, which is the cheaper
      // of the two losses. ③'s verbatim parts hold the same file body in
      // their functionCall args, so they go for the same reason; the
      // rebuilt turn keeps each call's own thoughtSignature. ②'s verbatim
      // items carry the same body in their function_call arguments.
      rawContentBlocks: null,
      rawModelParts: null,
      rawResponseItems: null,
      toolCalls: [
        for (final c in m.toolCalls)
          if (c.name == 'write_knowledge_file' &&
              (c.arguments['content']?.toString().length ?? 0) > 300)
            LLMToolCall(
              // id and thoughtSignature must survive verbatim: the id keeps
              // call/result pairing intact, and Gemini rejects the request
              // outright if a thoughtSignature is not echoed back as-is.
              id: c.id,
              name: c.name,
              thoughtSignature: c.thoughtSignature,
              arguments: {
                ...c.arguments,
                'content': '(elided to save context — this edit was already '
                    'staged and shown to the user.)',
              },
            )
          else
            c,
      ],
    );
  }
  return m;
}

/// Layer-2 fallback compaction: when even the trimmed history exceeds the
/// context budget, the conversation before the recent window is replaced by
/// a single LLM-generated summary message. If the summary cannot be made,
/// nothing is replaced and the next turn tries again.
/// The database keeps the original rows flagged `compacted` and re-appends
/// the new active history, so the full record stays inspectable.
Future<void> _maybeCompact(
  PromptOptimizerSession session,
  dynamic modelIdentifier,
  AssistantSessionRepository repo,
  String? contextId,
  void Function(String message)? onLog, {
  required String systemPrompt,
  required int? contextWindow,
  required double contextRatio,
  bool Function()? isCancelled,
}) async {
  final trimmed = _trimForSend(session.history);
  final occupied = PromptOptimizerAgent.occupiedChars(systemPrompt, trimmed);
  final budget = ContextBudget.budgetChars(
    contextWindow,
    contextRatio,
    observedCharsPerToken: session.observedCharsPerToken,
  );
  if (!PromptOptimizerAgent.shouldCompact(
    occupied: occupied,
    budgetChars: budget,
    messageCount: session.history.length,
  )) {
    return;
  }
  final boundary = PromptOptimizerAgent.compactionBoundary(
    session.history,
    systemPrompt: systemPrompt,
    budgetChars: budget,
    sizeTriggered: occupied >= budget,
  );
  if (boundary == null) {
    // Nothing worth folding. Worth saying out loud when it is the size
    // that triggered this: compaction only folds history, so it can never
    // shrink an oversized system prompt or the turns it always keeps, and
    // the request may fail with nothing but the provider's own error to
    // explain why.
    if (occupied >= budget) {
      onLog?.call('Context is over budget ($occupied/$budget chars) but there '
          'is nothing worth summarizing this turn — the system prompt or the '
          'most recent turns alone exceed the budget.');
    }
    return;
  }

  final head = session.history.sublist(0, boundary);
  // The latest delivery, when the fold takes it: appended to the summary by
  // the app rather than re-typed by the model (see `latestPromptMarker`).
  // Left alone while it still sits in the kept tail — the next compaction
  // that folds it will carry it forward then.
  final foldedLatestPrompt = _latestSubmittedPrompt(head, session.history);
  // Held as an object, not an index: the summary request below is awaited,
  // and nothing guarantees the history keeps its shape until it returns.
  final boundaryMsg = session.history[boundary];
  onLog?.call('Context budget reached ($occupied/$budget chars, '
      '${(contextRatio * 100).round()}% of the window) — summarizing '
      '${head.length} early messages.');
  String summaryText;
  try {
    final response = await PromptOptimizerAgent._request(
      modelIdentifier: modelIdentifier,
      messages: [
        LLMMessage(
          role: LLMRole.system,
          content: 'You compress a prompt-engineering conversation into a '
              'dense working summary. Keep, verbatim where possible: the '
              'user\'s core request and all confirmed design/character '
              'details; every knowledge-base file already consulted (paths '
              'only); the outcome of every generation-feedback round (which '
              'prompt version, what the user reported, what was changed in '
              'response); unresolved questions. Do NOT reproduce any '
              'submitted prompt: their text is omitted from the transcript, '
              'and the app appends the latest version after your summary — '
              'refer to it as "the latest prompt". Discard tool chatter. '
              'Answer with the summary only.',
        ),
        LLMMessage(role: LLMRole.user, content: _serializeForSummary(head)),
      ],
      contextId: contextId,
      options: const {'retryCount': 2, 'usageTag': 'compaction'},
      useStream: false,
      isCancelled: isCancelled,
    );
    summaryText = response.text.trim();
    if (summaryText.isEmpty) throw Exception('empty summary');
  } on LLMCancelled {
    // Compaction is a side quest inside a turn the user just stopped.
    // Rethrown rather than folded into the fallback below: falling back
    // would rewrite the session's history to a truncation summary as a
    // parting gift from a cancelled turn.
    rethrow;
  } catch (e) {
    // Failure atomicity (standard 10 §3.4): a failed or empty summary
    // changes nothing — not the history, not the stored rows. The old
    // fallback replaced the head with a one-line truncation note, turning a
    // single network blip into permanently lost context. This turn runs on
    // the uncompacted history (layer 1 still elides), and because the
    // trigger is re-evaluated at the top of every turn, the next one retries.
    onLog?.call('Summary generation failed ($e) — the history was left as '
        'it was; compaction will be retried next turn.');
    return;
  }

  final at = session.history.indexWhere((m) => identical(m, boundaryMsg));
  if (at < 0) {
    onLog?.call('History changed while the summary was generated — '
        'skipping this compaction.');
    return;
  }
  final summaryMsg = LLMMessage(
    role: LLMRole.user,
    content: '${PromptOptimizerAgent.summaryMarker}\n$summaryText'
        '${foldedLatestPrompt == null ? '' : '\n\n${PromptOptimizerAgent.latestPromptMarker} v${session.promptVersions}\n$foldedLatestPrompt'}',
  );
  final tail = session.history.sublist(at);
  session.history
    ..clear()
    ..addAll([summaryMsg, ...tail]);
  session.persistedCount = session.history.length;
  await repo.compactAll(session.id, session.history);
  session._addEntry(OptimizerChatEntry(
    kind: OptimizerEntryKind.notice,
    text: PromptOptimizerAgent.compactedNoticeToken,
  ));
}

/// Plain-text rendering of history for the summarization call. Tool results
/// are clipped hard — the summary needs decisions, not raw file contents.
/// The prompt of the latest `submit_prompt` call in [history] when that
/// call lies inside [head] (the part about to be folded), else null.
///
/// From the history, not from `session.refinedPrompt`: the summary replaces
/// exactly these messages, so what it carries forward must be what they
/// held. Older versions are not carried — the feedback rounds' outcomes,
/// which the summarizer keeps, are what distinguished them.
///
/// Once a fold has carried the prompt, the call itself is gone and the only
/// copy is the one appended to that summary — which is now in the head of
/// the next fold. So an earlier summary's appended prompt is carried forward
/// too, unless a newer call exists (in the tail, where it stays live, or in
/// the head, where it wins).
String? _latestSubmittedPrompt(List<LLMMessage> head, List<LLMMessage> history) {
  for (var i = history.length - 1; i >= 0; i--) {
    final m = history[i];
    if (m.role != LLMRole.assistant) continue;
    for (final call in m.toolCalls.reversed) {
      if (call.name != 'submit_prompt') continue;
      if (i >= head.length) return null;
      final prompt = call.arguments['prompt']?.toString() ?? '';
      return prompt.isEmpty ? null : prompt;
    }
  }
  for (final m in head.reversed) {
    if (m.role != LLMRole.user || !m.content.startsWith(PromptOptimizerAgent.summaryMarker)) continue;
    final carried = _appendedPromptOf(m.content);
    if (carried != null) return carried;
  }
  return null;
}

/// The prompt text appended to a summary message, or null when none was.
String? _appendedPromptOf(String summaryContent) {
  final at = summaryContent.indexOf('\n\n${PromptOptimizerAgent.latestPromptMarker}');
  if (at < 0) return null;
  final section = summaryContent.substring(at).trimLeft();
  final newline = section.indexOf('\n');
  if (newline < 0) return null;
  final prompt = section.substring(newline + 1);
  return prompt.isEmpty ? null : prompt;
}

String _serializeForSummary(List<LLMMessage> messages) {
  final buffer = StringBuffer();
  for (final m in messages) {
    switch (m.role) {
      case LLMRole.user:
        if (m.content.startsWith(PromptOptimizerAgent.viewResultMarker)) continue;
        // An earlier summary's appended prompt is not input for the next
        // one: the fold that made it appended it, and this fold appends the
        // latest again if it is going in.
        final content = m.content.startsWith(PromptOptimizerAgent.summaryMarker)
            ? m.content.split('\n\n${PromptOptimizerAgent.latestPromptMarker}').first
            : m.content;
        buffer.writeln('USER: $content');
      case LLMRole.assistant:
        if (m.content.trim().isNotEmpty) buffer.writeln('ASSISTANT: ${m.content.trim()}');
        for (final call in m.toolCalls) {
          if (call.name == 'submit_prompt') {
            // Body omitted: the app appends the latest version to the
            // summary itself, and no version's text is for the model to
            // re-type (the note is what changed, and it stays).
            final body = call.arguments['prompt']?.toString() ?? '';
            buffer.writeln('SUBMITTED PROMPT: (${body.length} chars, text omitted)'
                '${call.arguments['note'] != null ? ' — ${call.arguments['note']}' : ''}');
          } else if (call.name == 'ask_user') {
            final questions = AskUserQuestion.tryParse(call.arguments['questions']);
            buffer.writeln('USER WAS ASKED: '
                '${questions == null ? '(malformed questions)' : questions.map((q) => q.question).join(' | ')}');
          } else if (call.name == 'write_knowledge_file') {
            // The generic branch below would jsonEncode the whole proposed
            // file into the summarization prompt.
            final body = call.arguments['content']?.toString() ?? '';
            buffer.writeln('KB EDIT PROPOSED: ${call.arguments['path'] ?? ''} '
                '(${body.length} chars, content omitted)'
                '${call.arguments['note'] != null ? ' — ${call.arguments['note']}' : ''}');
          } else {
            buffer.writeln('TOOL CALL: ${call.name} ${jsonEncode(call.arguments)}');
          }
        }
      case LLMRole.tool:
        final clipped = m.content.length > 300 ? '${m.content.substring(0, 300)}…' : m.content;
        buffer.writeln('TOOL RESULT (${m.toolName}): $clipped');
      case LLMRole.system:
        break;
    }
  }
  return buffer.toString();
}
