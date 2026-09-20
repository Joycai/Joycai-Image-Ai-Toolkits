part of 'prompt_optimizer_agent.dart';

/// Conversation state for one prompt-assistant session.
///
/// Holds both the UI transcript and the raw LLM history (including tool
/// calls/results) so follow-up turns keep full context. Sessions are
/// persisted incrementally to the database and can be restored across app
/// restarts via [PromptOptimizerSession.fromStored].
class PromptOptimizerSession extends ChangeNotifier {
  static int _counter = 0;

  PromptOptimizerSession({AssistantMode mode = AssistantMode.systemPrompt, String? id})
      : _mode = mode,
        id = id ?? 'opt_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';

  final String id;

  /// Session title shown in the history list (first user message, truncated).
  String? title;

  /// How many [history] messages are already persisted to the database.
  int persistedCount = 0;

  /// What the session works from is fixed for its lifetime: a task-preset
  /// history and a knowledge-base history cannot continue each other, so that
  /// switch starts a new conversation. What a knowledge session is *used for*
  /// is not — see [switchKnowledgeUse].
  AssistantMode get mode => _mode;
  AssistantMode _mode;

  /// True for the two modes that work from the knowledge base.
  static bool isKnowledgeMode(AssistantMode mode) =>
      mode == AssistantMode.knowledgeBase || mode == AssistantMode.knowledgeEdit;

  /// Moves a knowledge session between writing prompts and maintaining the
  /// base (`A3d 4d`), keeping the conversation. Returns whether it switched.
  ///
  /// Safe where the cross-basis switch is not, because nothing in the history
  /// depends on which of the two it was: both read the same files through the
  /// same tools, and the write tools already come and go inside one session —
  /// a distill request attaches them for a turn ([hasPendingKbDistill]). The
  /// system prompt and the tool list are rebuilt per turn from [mode], so the
  /// switch takes effect on the next question. Edits already staged stay
  /// answerable: applying one is the user's act, gated on the card's state,
  /// not on the mode, and its outcome is still reported (invariant 11).
  ///
  /// Refused while a turn runs — the turn read [mode] when it started, and a
  /// mode that disagreed with the tools in flight would make the write gate
  /// in the tool handler answer for a different turn than the one asking —
  /// and refused across the basis, which is a new session's job. Both are
  /// also held off by the UI; this is the gate that holds if the UI is wrong.
  ///
  /// The divider it leaves in the transcript is a fact about the interface,
  /// not something said to the model, so it is not written to [history]: a
  /// restored session does not replay it.
  bool switchKnowledgeUse(AssistantMode next) {
    if (_isRunning || next == _mode) return false;
    if (!isKnowledgeMode(_mode) || !isKnowledgeMode(next)) return false;
    _mode = next;
    final notice = OptimizerChatEntry(
      kind: OptimizerEntryKind.notice,
      text: next == AssistantMode.knowledgeEdit
          ? PromptOptimizerAgent.kbUseMaintainNoticeToken
          : PromptOptimizerAgent.kbUseWriteNoticeToken,
    );
    if (_transcript.isEmpty) {
      // Nothing to divide yet; the panel and the empty state already say it.
      notifyListeners();
    } else if (_isKbUseNotice(_transcript.last)) {
      // Toggled again with nothing said in between: one divider, the latest.
      // Replaced, not removed — the transcript only ever grows, and the chat
      // keys its rows by index.
      _transcript = [..._transcript.sublist(0, _transcript.length - 1), notice];
      notifyListeners();
    } else {
      _addEntry(notice);
    }
    return true;
  }

  static bool _isKbUseNotice(OptimizerChatEntry e) =>
      e.kind == OptimizerEntryKind.notice &&
      (e.text == PromptOptimizerAgent.kbUseMaintainNoticeToken ||
          e.text == PromptOptimizerAgent.kbUseWriteNoticeToken);

  /// True when the session needs a validated knowledge base to run at all.
  /// Prefer this over comparing [mode] directly — the checks live in several
  /// files and an omitted one leaves the mode silently inert.
  bool get usesKnowledgeBase => isKnowledgeMode(mode);

  /// What the agent may do to the knowledge base this turn.
  ///
  /// Held on the session rather than threaded through [runTurn]: the tool
  /// handler, the approval gate and the panel all consult it, and every one of
  /// them already has the session. Assigned from the persisted setting just
  /// before a turn is enqueued, so a toggle flipped mid-conversation takes
  /// effect on the next question rather than on the one already in flight.
  KbWritePolicy writePolicy = KbWritePolicy.defaults;

  /// True when the agent may propose knowledge-base edits.
  ///
  /// Both halves matter. The mode (or a pending distill request — see
  /// [hasPendingKbDistill]) is what makes editing the point of the turn; the
  /// policy is the user's standing answer to whether that is currently
  /// allowed, and turning it off has to withdraw the tool rather than merely
  /// hide its button — a model offered a tool will find a reason to call it.
  ///
  /// A distill request escalates a [AssistantMode.knowledgeBase] session
  /// rather than requiring the user to have picked the maintenance mode up
  /// front — nobody knows at session start whether a tuning run will end up
  /// worth distilling. The escalation is derived from history, so it survives
  /// restore and expires the moment the user sends their next ordinary
  /// message.
  bool get canWriteKnowledge =>
      (mode == AssistantMode.knowledgeEdit ||
          (mode == AssistantMode.knowledgeBase && hasPendingKbDistill)) &&
      writePolicy.allowWrites;

  /// True while the most recent *real* user turn is a distill request
  /// ([PromptOptimizerAgent.kbDistillMarker]).
  ///
  /// Derived from [history] rather than tracked in a flag (invariant: derive,
  /// don't track — see assistant-context.md): tool results, view-image
  /// attachments and ask_user answers appended during the distill turn do not
  /// clear it — the model may keep its write tools across an ask_user round
  /// trip — while the user's next ordinary message does.
  bool get hasPendingKbDistill {
    for (int i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (!_isRealUserTurn(m)) continue;
      // A free-text answer to a pending ask_user is a *continuation* of the
      // turn that asked, not a new request, and must not clear the
      // escalation — otherwise a distill turn that paused on an ask_user
      // (its rule 4: contradictions) and was answered in the composer loses
      // its write tools on resume. It is appended right after the tool
      // result that pairs the dangling call (resolvePendingAskUserAsFreeText),
      // so skip it and keep walking back to the request that opened the turn.
      //
      // "Preceded by a tool message" is NOT the test: a mid-batch stop, the
      // round limit and a request that failed after a tool round all leave
      // the history ending on a tool result too, and the user's next ordinary
      // message would then inherit the distill turn's write access (standard
      // 08 §3.5). Only that specific free-text reply counts. The card path
      // needs no exception — it appends a tool message, never a user turn.
      if (i > 0 && _isFreeTextAskUserReply(history[i - 1])) continue;
      return m.content.startsWith(PromptOptimizerAgent.kbDistillMarker);
    }
    return false;
  }

  /// Chars-per-token measured from the last request the provider reported
  /// token usage for, or null while it has reported none.
  ///
  /// Lets the budget fit the user's actual content — English runs ~4
  /// chars/token, Chinese ~1–1.3, and a constant cannot serve both — while
  /// staying entirely optional: providers may omit usage, and then the
  /// conservative default applies.
  double? observedCharsPerToken;

  /// Chars of the two fixed parts of the last request that went out: the system
  /// prompt, and the JSON schemas of the tools offered with it.
  ///
  /// Recorded rather than derived, because neither is reconstructible from the
  /// session: the system prompt is assembled per turn from a mode, a preset and
  /// (in knowledge mode) a file read off disk, and the tool list shrinks
  /// mid-turn when the window runs out. Both are zero until the first request —
  /// [PromptOptimizerAgent.measureContext] reports that as "nothing measured
  /// yet" rather than as a free system prompt.
  int systemPromptChars = 0;
  int toolSchemaChars = 0;

  /// Records what the request about to go out costs before the history.
  ///
  /// Notifies, so the usage readout follows the turn as it runs rather than
  /// only at the end of it — the tool list changes between requests of the same
  /// turn, and so does everything downstream of a tool result.
  void recordRequestBasis({required int systemPromptChars, required int toolSchemaChars}) {
    if (this.systemPromptChars == systemPromptChars &&
        this.toolSchemaChars == toolSchemaChars) {
      return;
    }
    this.systemPromptChars = systemPromptChars;
    this.toolSchemaChars = toolSchemaChars;
    notifyListeners();
  }

  /// For each knowledge file written this session, the last [history] message
  /// at the moment of the write (null when the history was empty): reads
  /// strictly after it are current, reads at or before it are not.
  ///
  /// A plain "is stale" flag would be unsatisfiable: the read-before-write
  /// rail would reject the very re-read that is supposed to clear it, and the
  /// model could never edit the same file twice in one session.
  ///
  /// Keyed by message identity, never by index (standard 10 §3.2): compaction
  /// shrinks the history and the pairing repair inserts stubs, and an index
  /// survives neither — after a compaction it pointed past the end of the
  /// history, so no re-read of the file ever counted again. A marker that is
  /// no longer in the history was folded into a summary, which means every
  /// read still present came after the write.
  final Map<String, LLMMessage?> knowledgeStaleAt = {};

  List<OptimizerChatEntry> _transcript = [];
  List<OptimizerChatEntry> get transcript => _transcript;

  /// Full LLM conversation (system message excluded — it is supplied per turn
  /// so the user can switch presets mid-conversation).
  final List<LLMMessage> history = [];

  /// Paths of reference images the model has already viewed (drives the
  /// "viewed" badge in the reference panel and avoids re-attaching).
  Set<String> _viewedImagePaths = {};
  Set<String> get viewedImagePaths => _viewedImagePaths;

  /// The most recently staged optimized prompt.
  String? refinedPrompt;
  int promptVersions = 0;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// When the turn now running began, or null while nothing is running.
  ///
  /// Kept here rather than derived, because there is nothing in the transcript
  /// to derive it from: a turn that has not yet called a tool has appended
  /// nothing at all, and that is exactly the stretch the user most wants a
  /// clock for. `10i` puts the elapsed time on the timeline card.
  DateTime? _runStartedAt;
  DateTime? get runStartedAt => _runStartedAt;

  /// Characters of tool-call arguments the request in flight has streamed,
  /// or null when no call is streaming.
  ///
  /// The stretch this covers is the one that looked hung: a `submit_prompt`
  /// runs to thousands of characters, streams for minutes, and appends
  /// nothing to the transcript until it is whole — so users stopped turns
  /// that were working. Its own notifier rather than [notifyListeners]: it
  /// ticks per fragment, and only the timeline's working row reads it.
  final ValueNotifier<int?> streamingToolArgumentChars = ValueNotifier(null);

  /// A channel merge moved [idMap]'s models onto the ones they merged into:
  /// the replies' model links follow, in the transcript and in [history] —
  /// the stored rows are rewritten by the repository, but a compaction writes
  /// [history] back whole, and an open conversation's links are these.
  void remapModelLinks(Map<int, int> idMap) {
    var changed = false;
    for (var i = 0; i < history.length; i++) {
      final to = idMap[history[i].modelDbId];
      if (to == null) continue;
      history[i] = history[i].withModelDbId(to);
      changed = true;
    }
    if (_transcript.any((e) => idMap.containsKey(e.modelDbId))) {
      _transcript = [
        for (final e in _transcript)
          idMap[e.modelDbId] == null ? e : e.copyWith(modelDbId: idMap[e.modelDbId]),
      ];
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void addUserTurn(String text) {
    history.add(LLMMessage(role: LLMRole.user, content: text));
    _addEntry(OptimizerChatEntry(kind: OptimizerEntryKind.user, text: text));
  }

  /// Appends the user's feedback on a generated result: which prompt
  /// [promptVersion] produced it, which attached image ([imageName]) shows it,
  /// and what the user says is wrong (or right) about it.
  ///
  /// Encoded as a marker-prefixed user message with a one-line JSON header so
  /// everything downstream can *derive* it from history — the transcript on
  /// restore, the iteration ledger, and the result-image metadata that
  /// `list_reference_images` reports. The image itself is NOT attached here:
  /// it goes into the reference list (kind "result") and the model views it
  /// lazily via `view_image`, exactly like any other reference, so the
  /// attachment economics (eliding, re-view liveness) stay unchanged.
  ///
  /// Binding to the image is by name: the reference list is keyed positionally
  /// per turn, so a path would be the only stable alternative — and paths do
  /// not belong in content shipped to a provider. A same-named collision
  /// merely mislabels the listing metadata, never the feedback text.
  ///
  /// [satisfied] and [reasons] (`3b`) ride the JSON header, not the body:
  /// the body stays the user's own words — possibly none, a rating alone is
  /// a complete report — and the header is what every reader parses.
  void addResultFeedback({
    required String imageName,
    required int promptVersion,
    required String feedback,
    bool? satisfied,
    List<ResultFeedbackReason> reasons = const [],
  }) {
    final header = jsonEncode({
      'prompt_version': promptVersion,
      'image': imageName,
      if (satisfied != null) 'rating': satisfied ? 'satisfied' : 'unsatisfied',
      if (reasons.isNotEmpty) 'reasons': [for (final r in reasons) r.wireId],
    });
    history.add(LLMMessage(
      role: LLMRole.user,
      content: '${PromptOptimizerAgent.resultFeedbackMarker} $header\n${feedback.trim()}',
    ));
    _addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.resultFeedback,
      text: feedback.trim(),
      version: promptVersion,
      note: imageName,
      feedbackSatisfied: satisfied,
      feedbackReasons: reasons,
    ));
  }

  /// Appends a distill-request turn. [content] must already carry
  /// [PromptOptimizerAgent.kbDistillMarker] — composed by
  /// `stageKbDistillRequest`, which owns the instruction wording and the
  /// iteration ledger it embeds. Only meaningful in knowledge sessions.
  void addKbDistillTurn(String content) {
    assert(content.startsWith(PromptOptimizerAgent.kbDistillMarker));
    assert(usesKnowledgeBase);
    history.add(LLMMessage(role: LLMRole.user, content: content));
    _addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.kbDistill,
      text: PromptOptimizerAgent.kbDistillNoticeToken,
    ));
  }

  void _addEntry(OptimizerChatEntry entry) {
    _transcript = [..._transcript, entry];
    notifyListeners();
  }

  void _markViewed(String path) {
    _viewedImagePaths = {..._viewedImagePaths, path};
    notifyListeners();
  }

  void _stagePrompt(String prompt, String? note) {
    refinedPrompt = prompt;
    promptVersions++;
    _addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.prompt,
      text: prompt,
      version: promptVersions,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
    ));
  }

  int _kbEditCounter = 0;

  /// `root|relPath` of every knowledge file already backed up this session.
  /// Only the first write of a file is backed up, so its `.bak` keeps the
  /// version from before the session touched it. In memory: a restored session
  /// starts over, and its first write backs up again.
  final Set<String> _backedUpPaths = {};

  /// Edit ids whose outcome the model has already been told — by an
  /// outcomes record, or by the tool result of an edit applied without
  /// confirmation. In memory only; see invariant 11.
  final Set<String> _reportedKbEditIds = {};

  /// Stages a proposed knowledge-file edit for the user to approve. Nothing
  /// touches disk here — same contract as [_stagePrompt].
  String _stageKbEdit({
    required String relPath,
    required String newContent,
    required String? oldContent,
    String? knowledgeRoot,
    String? note,
    KbEditScope scope = KbEditScope.file,
    String? section,
  }) {
    final editId = 'kbedit_${id}_${_kbEditCounter++}';
    _addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.kbEdit,
      text: relPath,
      editId: editId,
      targetPath: relPath,
      newContent: newContent,
      oldContent: oldContent,
      knowledgeRoot: knowledgeRoot,
      editState: KbEditState.pending,
      editScope: scope,
      editSection: section,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
    ));
    return editId;
  }

  /// Flips a staged edit to its terminal state. Rebuilds the transcript rather
  /// than mutating the entry in place; because the length is unchanged, the
  /// chat view re-renders without yanking the user's scroll position.
  void _resolveKbEdit(String editId, KbEditState state, {String? error}) {
    _transcript = [
      for (final e in _transcript)
        (e.kind == OptimizerEntryKind.kbEdit && e.editId == editId)
            ? e.copyWith(editState: state, editError: error)
            : e,
    ];
    notifyListeners();
  }

  /// Puts the session into the state `10i` draws, without a live turn.
  ///
  /// The running state is otherwise only reachable by actually calling a
  /// model, which neither the screenshot harness nor a widget test can do —
  /// and it is the state with the most UI of its own.
  @visibleForTesting
  void setRunningForTest(bool running) => _setRunning(running);

  /// Flips a staged edit's state without touching disk — the real
  /// [PromptOptimizerAgent.applyStagedKbEdit] writes through
  /// [KnowledgeBaseService], which a widget test has no folder for.
  @visibleForTesting
  void resolveKbEditForTest(String editId, KbEditState state) =>
      _resolveKbEdit(editId, state);

  @visibleForTesting
  String stageKbEditForTest({
    required String relPath,
    required String newContent,
    String? oldContent,
    String? knowledgeRoot,
    String? note,
    KbEditScope scope = KbEditScope.file,
    String? section,
  }) =>
      _stageKbEdit(
        relPath: relPath,
        newContent: newContent,
        oldContent: oldContent,
        knowledgeRoot: knowledgeRoot,
        note: note,
        scope: scope,
        section: section,
      );

  /// The proposed content of the newest still-pending edit to [relPath], or
  /// null when none is waiting: what a further section edit to the same
  /// file in the same turn builds on.
  String? _pendingKbEditContent(String relPath) {
    for (final e in _transcript.reversed) {
      if (e.kind == OptimizerEntryKind.kbEdit && e.targetPath == relPath) {
        return e.editState == KbEditState.pending ? e.newContent : null;
      }
    }
    return null;
  }

  OptimizerChatEntry? _findKbEdit(String editId) {
    for (final e in _transcript) {
      if (e.kind == OptimizerEntryKind.kbEdit && e.editId == editId) return e;
    }
    return null;
  }

  /// Stages a structured-question card. The paired tool result is deliberately
  /// NOT appended here — the call stays dangling in [history] until the user
  /// answers (or the turn self-heals), which is what makes the pending state
  /// derivable and restorable.
  void _stageAskUser(String callId, List<AskUserQuestion> questions) {
    _addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.askUser,
      text: '',
      askCallId: callId,
      askQuestions: questions,
      askState: AskUserState.pending,
    ));
  }

  /// Flips a question card to its terminal state. Same rebuild-not-mutate and
  /// length-preserving contract as [_resolveKbEdit].
  void _resolveAskUser(String callId, AskUserState state, {List<AskUserAnswer>? answers}) {
    _transcript = [
      for (final e in _transcript)
        (e.kind == OptimizerEntryKind.askUser && e.askCallId == callId)
            ? e.copyWith(askState: state, askAnswers: answers)
            : e,
    ];
    notifyListeners();
  }

  /// The trailing unanswered `ask_user` call, or null.
  ///
  /// Derived from [history] on every access rather than tracked in a flag
  /// (invariant: derive, don't track — see assistant-context.md). Scans from
  /// the end: the pending call, if any, is the last `ask_user` call with no
  /// matching tool result after it. Works identically for live and restored
  /// sessions.
  ({String callId, List<AskUserQuestion> questions})? get pendingAskUser {
    final answered = <String>{};
    for (int i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (m.role == LLMRole.tool) {
        if (m.toolName == 'ask_user' && m.toolCallId != null) answered.add(m.toolCallId!);
        continue;
      }
      if (m.role != LLMRole.assistant) continue;
      final askCalls = [for (final c in m.toolCalls) if (c.name == 'ask_user') c];
      if (askCalls.isEmpty) continue;
      // Only the LAST assistant message carrying ask_user calls can hold a
      // dangling one: a dangling call ends the turn, so no later assistant
      // message can exist until it is paired. Within the batch, malformed or
      // duplicate calls were answered with error results immediately — the
      // pending one is whichever has no result yet.
      for (final call in askCalls) {
        if (answered.contains(call.id)) continue;
        final questions = AskUserQuestion.tryParse(call.arguments['questions']);
        // Unparseable would have received an error result in the same batch,
        // so a dangling unparseable call means corrupt data — not pending.
        if (questions == null) continue;
        return (callId: call.id, questions: questions);
      }
      return null;
    }
    return null;
  }

  /// Applies [PromptOptimizerAgent.repairToolCallPairing] to the live history.
  ///
  /// [persistedCount] is rebased rather than reset: everything before the
  /// first message that was not yet persisted stays "persisted" — stubs placed
  /// there are not written, and every later restore re-derives them the same
  /// way — while the unpersisted tail is still appended at the next sync.
  /// Returns whether anything changed.
  bool _repairToolCallPairing() {
    final repaired = _repairPairingWithOrigins(history);
    final unchanged = repaired.length == history.length &&
        [for (int i = 0; i < repaired.length; i++) identical(repaired[i].message, history[i])]
            .every((same) => same);
    if (unchanged) return false;

    var rebased = repaired.length;
    for (int k = 0; k < repaired.length; k++) {
      final origin = repaired[k].origin;
      if (origin != null && origin >= persistedCount) {
        rebased = k;
        break;
      }
    }
    // Stale markers point at message objects. A rewritten message hands its
    // marker to its replacement; a dropped one to the nearest message kept
    // before it — "reads after the marker" still names the same reads.
    final byOrigin = <int, LLMMessage>{
      for (final e in repaired)
        if (e.origin != null) e.origin!: e.message,
    };
    for (int i = 0; i < history.length; i++) {
      final old = history[i];
      if (!knowledgeStaleAt.values.any((v) => identical(v, old))) continue;
      LLMMessage? to;
      for (int j = i; j >= 0; j--) {
        final kept = byOrigin[j];
        if (kept != null) {
          to = kept;
          break;
        }
      }
      if (!identical(to, old)) _carryStaleMarker(old, to);
    }

    history
      ..clear()
      ..addAll([for (final e in repaired) e.message]);
    persistedCount = rebased;
    return true;
  }

  /// Re-points every [knowledgeStaleAt] marker at [from] to [to] — for the
  /// places that replace a history message with a rewritten copy.
  void _carryStaleMarker(LLMMessage from, LLMMessage? to) {
    for (final key in [...knowledgeStaleAt.keys]) {
      if (identical(knowledgeStaleAt[key], from)) knowledgeStaleAt[key] = to;
    }
  }

  void _setRunning(bool running) {
    if (_isRunning == running) return;
    _isRunning = running;
    _runStartedAt = running ? DateTime.now() : null;
    streamingToolArgumentChars.value = null;
    notifyListeners();
  }

  /// Rebuilds a session (transcript, viewed images, staged prompt) from
  /// persisted [history]. The transcript is derived rather than stored:
  /// user/assistant text maps 1:1 and tool activity is recovered from the
  /// assistant messages' tool calls.
  factory PromptOptimizerSession.fromStored({
    required String id,
    required AssistantMode mode,
    String? title,
    required List<LLMMessage> history,
    bool hasCompactedHistory = false,
    String? compactedNoticeText,
    String? missingImageNoticeText,
  }) {
    final session = PromptOptimizerSession(mode: mode, id: id);
    session.title = title;
    // Stored rows can be individually dropped (corrupt JSON, an unknown role)
    // and a crash can land between an assistant message and its results, so
    // the replayed history is not trusted to be pairable: an unanswered call
    // or an orphan result would 400 every later request of the session. The
    // repair is deterministic, so the stored rows keep their old shape and
    // every restore derives the same repaired list — which is why all of it
    // counts as persisted.
    final restored = PromptOptimizerAgent.repairToolCallPairing(history);
    session.history.addAll(restored);
    session.persistedCount = restored.length;

    final entries = <OptimizerChatEntry>[];
    if (hasCompactedHistory && compactedNoticeText != null) {
      entries.add(OptimizerChatEntry(kind: OptimizerEntryKind.notice, text: compactedNoticeText));
    }
    bool anyImageMissing = false;
    for (int msgIndex = 0; msgIndex < restored.length; msgIndex++) {
      final msg = restored[msgIndex];
      switch (msg.role) {
        case LLMRole.user:
          if (msg.content.startsWith(PromptOptimizerAgent.viewResultMarker)) {
            // Synthetic image-attach message: recover the viewed path.
            for (final att in msg.attachments) {
              final path = att.path;
              if (path != null) {
                session._viewedImagePaths = {...session._viewedImagePaths, path};
                if (!File(path).existsSync()) anyImageMissing = true;
              }
            }
          } else if (msg.content.startsWith(PromptOptimizerAgent.summaryMarker)) {
            // A compaction summary is context for the model, not a chat
            // line — but the delivery it carries is the session's latest
            // prompt: the call it came from was folded away, so nothing
            // later in the history re-seeds it. The version label keeps the
            // counter where it was, so the next delivery is not numbered
            // below the ones the summary talks about.
            final carried = _appendedPromptOf(msg.content);
            if (carried != null) {
              session.refinedPrompt = carried.prompt;
              final version = carried.version ?? (session.promptVersions + 1);
              if (version > session.promptVersions) session.promptVersions = version;
            }
          } else if (msg.content.startsWith(PromptOptimizerAgent.kbEditOutcomesMarker)) {
            // Edit-outcome records are context for the model, not chat lines.
          } else if (msg.content.startsWith(PromptOptimizerAgent.resultFeedbackMarker)) {
            final parsed = PromptOptimizerAgent.tryParseResultFeedback(msg.content);
            // A header that fails to parse degrades to a plain user bubble —
            // the text is still the user's words, only the card dressing is lost.
            entries.add(parsed == null
                ? OptimizerChatEntry(kind: OptimizerEntryKind.user, text: msg.content)
                : OptimizerChatEntry(
                    kind: OptimizerEntryKind.resultFeedback,
                    text: parsed.feedback,
                    version: parsed.promptVersion,
                    note: parsed.imageName,
                    feedbackSatisfied: parsed.satisfied,
                    feedbackReasons: parsed.reasons,
                  ));
          } else if (msg.content.startsWith(PromptOptimizerAgent.kbDistillMarker)) {
            entries.add(OptimizerChatEntry(
              kind: OptimizerEntryKind.kbDistill,
              text: PromptOptimizerAgent.kbDistillNoticeToken,
            ));
          } else {
            entries.add(OptimizerChatEntry(kind: OptimizerEntryKind.user, text: msg.content));
          }
        case LLMRole.assistant:
          if (msg.content.trim().isNotEmpty) {
            entries.add(OptimizerChatEntry(
              kind: OptimizerEntryKind.assistant,
              text: msg.content.trim(),
              truncated: msg.truncated,
              deliverable: msg.deliverable,
              modelDbId: msg.modelDbId,
            ));
          }
          for (final call in msg.toolCalls) {
            switch (call.name) {
              case 'submit_prompt':
                final prompt = call.arguments['prompt']?.toString() ?? '';
                if (prompt.trim().isEmpty) break;
                session.refinedPrompt = prompt;
                session.promptVersions++;
                final note = call.arguments['note']?.toString();
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.prompt,
                  text: prompt,
                  version: session.promptVersions,
                  note: (note == null || note.trim().isEmpty) ? null : note.trim(),
                ));
              case 'view_image':
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.tool,
                  text: call.arguments['id']?.toString() ?? '',
                  toolName: 'view_image',
                ));
              case 'read_knowledge_file':
                // No cache to rebuild: whether a read is still readable is
                // derived from the restored history by _liveReadPages.
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.tool,
                  text: call.arguments['path']?.toString() ?? '',
                  toolName: 'read_knowledge_file',
                ));
              case 'write_knowledge_file':
                // Restored as a plain chip, never as an actionable kbEdit card.
                // The approval outcome is not persisted (the transcript is
                // derived from history, which only records that the call
                // happened), and oldContent was captured at staging time — so
                // re-offering Apply after a restart could overwrite newer
                // content against a stale preview.
                final writtenPath = call.arguments['path']?.toString() ?? '';
                // For the same reason the card is inert, we cannot know whether
                // this edit was applied — so assume it was. Treating earlier
                // reads of the file as current would let the model overwrite
                // it while diffing against pre-edit content; the cost of being
                // wrong is one redundant re-read.
                if (writtenPath.isNotEmpty) {
                  session.knowledgeStaleAt[writtenPath] = msg;
                }
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.tool,
                  text: writtenPath,
                  toolName: 'write_knowledge_file',
                ));
              case 'list_knowledge_files':
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.tool,
                  text: '',
                  toolName: 'list_knowledge_files',
                ));
              case 'delegate':
                // A plain chip: the note (if one was stored) lives in the DB
                // keyed by session, so read_note keeps working after a
                // restart — nothing else to rebuild.
                final delegatedTask = call.arguments['task']?.toString() ?? '';
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.tool,
                  text: delegatedTask.length > 120
                      ? '${delegatedTask.substring(0, 120)}…'
                      : delegatedTask,
                  toolName: 'delegate',
                ));
              case 'read_note':
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.tool,
                  text: '#${call.arguments['note_id'] ?? ''}',
                  toolName: 'read_note',
                ));
              case 'list_reference_images':
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.tool,
                  text: '',
                  toolName: 'list_reference_images',
                ));
              case 'ask_user':
                final questions = AskUserQuestion.tryParse(call.arguments['questions']);
                if (questions == null) break; // Malformed call: was error-answered, no card.
                // Look ahead for the paired result. Found → collapsed card;
                // dangling → a fully actionable pending card: unlike a restored
                // kbEdit (inert, could clobber newer disk content), answering
                // only appends a message, so it is safe to keep live.
                LLMMessage? result;
                for (int j = msgIndex + 1; j < restored.length; j++) {
                  final r = restored[j];
                  if (r.role == LLMRole.tool && r.toolCallId == call.id) {
                    result = r;
                    break;
                  }
                }
                if (result == null) {
                  entries.add(OptimizerChatEntry(
                    kind: OptimizerEntryKind.askUser,
                    text: '',
                    askCallId: call.id,
                    askQuestions: questions,
                    askState: AskUserState.pending,
                  ));
                  break;
                }
                var state = AskUserState.dismissed;
                List<AskUserAnswer>? answers;
                try {
                  final decoded = jsonDecode(result.content);
                  if (decoded is Map && decoded['status'] == 'ok') {
                    final rawAnswers = decoded['answers'];
                    if (rawAnswers is List) {
                      state = AskUserState.answered;
                      answers = [
                        for (final a in rawAnswers)
                          if (a is Map)
                            AskUserAnswer(
                              header: a['header']?.toString() ?? '',
                              selected: [
                                if (a['selected'] is List)
                                  for (final s in a['selected'] as List) s.toString(),
                              ],
                              otherText: a['other']?.toString(),
                            ),
                      ];
                    }
                    // status ok without answers = free-text reply → dismissed.
                  }
                } catch (_) {
                  // Undecodable result degrades to a bare dismissed card.
                }
                entries.add(OptimizerChatEntry(
                  kind: OptimizerEntryKind.askUser,
                  text: '',
                  askCallId: call.id,
                  askQuestions: questions,
                  askState: state,
                  askAnswers: answers,
                ));
            }
          }
        case LLMRole.tool:
        case LLMRole.system:
          break; // Tool results and system prompts are not chat lines.
      }
    }
    if (anyImageMissing && missingImageNoticeText != null) {
      entries.add(OptimizerChatEntry(kind: OptimizerEntryKind.notice, text: missingImageNoticeText));
    }
    session._transcript = entries;
    return session;
  }
}

/// The request [PromptOptimizerAgent] makes, as tests replace it — see
/// [PromptOptimizerAgent.debugRequestOverride].
typedef AgentRequestFn = Future<LLMResponse> Function(
  List<LLMMessage> messages,
  List<LLMTool>? tools,
  Map<String, dynamic> options,
);
