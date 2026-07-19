import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'database_service.dart';
import 'knowledge_base_service.dart';
import 'llm/context_budget.dart';
import 'llm/llm_service.dart';
import 'llm/llm_types.dart';
import 'repositories/assistant_session_repository.dart';

/// Operating mode of the prompt assistant.
///
///  * [systemPrompt] — classic behavior: the user picks a system-prompt
///    preset (or writes a custom one) that steers the optimization.
///  * [knowledgeBase] — the assistant works as an agent over the user's local
///    knowledge base folder: it reads rule/template files on demand
///    (progressive disclosure) and builds prompts according to them. Uses a
///    built-in system prompt; user presets do not apply.
///  * [knowledgeEdit] — maintenance mode: everything [knowledgeBase] can do,
///    plus proposing edits to the knowledge files themselves. Edits are staged
///    for the user to preview and approve; the agent never writes to disk.
///
/// Persisted by name with a fallback, so adding a value stays backward
/// compatible — an older build restoring a newer row degrades to
/// [systemPrompt] rather than failing.
enum AssistantMode { systemPrompt, knowledgeBase, knowledgeEdit }

/// Lifecycle of a knowledge-base edit proposed by the agent.
///
/// [failed] is a real state, not defensive padding: the disk write happens when
/// the user taps Apply, so it can fail long after the tool call returned ok.
enum KbEditState { pending, applied, rejected, failed }

/// Lifecycle of a structured question the agent asked via `ask_user`.
///
/// [dismissed] covers both "the user answered in free text instead" and "the
/// question was cancelled" — either way the card is no longer actionable and
/// the pending tool call has been paired.
enum AskUserState { pending, answered, dismissed }

/// One selectable option of an [AskUserQuestion].
class AskUserOption {
  final String label;
  final String? description;

  const AskUserOption({required this.label, this.description});
}

/// One structured question the agent asks the user via the `ask_user` tool.
class AskUserQuestion {
  /// Very short label (2-3 words) shown as the question's title.
  final String header;

  /// The full question text.
  final String question;

  /// Whether the user may pick several options.
  final bool multiSelect;

  final List<AskUserOption> options;

  const AskUserQuestion({
    required this.header,
    required this.question,
    required this.multiSelect,
    required this.options,
  });

  static const int maxQuestions = 4;
  static const int minOptions = 2;
  static const int maxOptions = 4;

  /// Parses the `questions` argument of an `ask_user` call. Strict: 1-4
  /// questions, each with a non-empty header/question and 2-4 non-empty
  /// option labels. Returns null on any violation so the caller can answer
  /// the tool call with a schema error instead of staging a broken card.
  static List<AskUserQuestion>? tryParse(Object? questionsArg) {
    if (questionsArg is! List || questionsArg.isEmpty || questionsArg.length > maxQuestions) {
      return null;
    }
    final questions = <AskUserQuestion>[];
    for (final raw in questionsArg) {
      if (raw is! Map) return null;
      final header = raw['header']?.toString().trim() ?? '';
      final question = raw['question']?.toString().trim() ?? '';
      if (header.isEmpty || question.isEmpty) return null;
      // Models routinely quote scalars — accept the string forms of booleans.
      final rawMulti = raw['multi_select'];
      final multiSelect = rawMulti == true || rawMulti?.toString() == 'true';
      final rawOptions = raw['options'];
      if (rawOptions is! List ||
          rawOptions.length < minOptions ||
          rawOptions.length > maxOptions) {
        return null;
      }
      final options = <AskUserOption>[];
      for (final o in rawOptions) {
        if (o is! Map) return null;
        final label = o['label']?.toString().trim() ?? '';
        if (label.isEmpty) return null;
        final description = o['description']?.toString().trim();
        options.add(AskUserOption(
          label: label,
          description: (description == null || description.isEmpty) ? null : description,
        ));
      }
      questions.add(AskUserQuestion(
        header: header,
        question: question,
        multiSelect: multiSelect,
        options: options,
      ));
    }
    return questions;
  }
}

/// The user's answer to one [AskUserQuestion].
class AskUserAnswer {
  final String header;

  /// Labels of the chosen options (empty when only free text was given).
  final List<String> selected;

  /// Free-text supplement or replacement ("Other…" field).
  final String? otherText;

  const AskUserAnswer({required this.header, required this.selected, this.otherText});

  Map<String, dynamic> toJson() => {
        'header': header,
        'selected': selected,
        if (otherText != null && otherText!.trim().isNotEmpty) 'other': otherText!.trim(),
      };
}

/// Kinds of entries shown in the optimizer chat transcript.
enum OptimizerEntryKind { user, assistant, tool, prompt, error, notice, kbEdit, askUser }

/// One rendered line of the optimizer conversation.
class OptimizerChatEntry {
  final OptimizerEntryKind kind;
  final String text;

  /// For [OptimizerEntryKind.prompt]: 1-based version number of the staged prompt.
  final int? version;

  /// For [OptimizerEntryKind.prompt]: the model's short note about this revision.
  final String? note;

  /// For [OptimizerEntryKind.tool]: which tool ran ('list_reference_images' /
  /// 'view_image').
  final String? toolName;

  /// For [OptimizerEntryKind.kbEdit]: identifies this edit within the session.
  final String? editId;

  /// For [OptimizerEntryKind.kbEdit]: knowledge-base-relative target path.
  final String? targetPath;

  /// For [OptimizerEntryKind.kbEdit]: the full proposed file content.
  final String? newContent;

  /// For [OptimizerEntryKind.kbEdit]: content at staging time; null = create.
  final String? oldContent;

  /// For [OptimizerEntryKind.kbEdit]: approval state.
  final KbEditState? editState;

  /// For [OptimizerEntryKind.askUser]: the tool-call id this card must answer.
  final String? askCallId;

  /// For [OptimizerEntryKind.askUser]: the structured questions.
  final List<AskUserQuestion>? askQuestions;

  /// For [OptimizerEntryKind.askUser]: lifecycle state of the card.
  final AskUserState? askState;

  /// For [OptimizerEntryKind.askUser]: the answers, once given (for the
  /// collapsed "answered" rendering).
  final List<AskUserAnswer>? askAnswers;

  OptimizerChatEntry({
    required this.kind,
    required this.text,
    this.version,
    this.note,
    this.toolName,
    this.editId,
    this.targetPath,
    this.newContent,
    this.oldContent,
    this.editState,
    this.askCallId,
    this.askQuestions,
    this.askState,
    this.askAnswers,
  });

  OptimizerChatEntry copyWith({
    KbEditState? editState,
    AskUserState? askState,
    List<AskUserAnswer>? askAnswers,
  }) =>
      OptimizerChatEntry(
        kind: kind,
        text: text,
        version: version,
        note: note,
        toolName: toolName,
        editId: editId,
        targetPath: targetPath,
        newContent: newContent,
        oldContent: oldContent,
        editState: editState ?? this.editState,
        askCallId: askCallId,
        askQuestions: askQuestions,
        askState: askState ?? this.askState,
        askAnswers: askAnswers ?? this.askAnswers,
      );
}

/// Conversation state for one prompt-assistant session.
///
/// Holds both the UI transcript and the raw LLM history (including tool
/// calls/results) so follow-up turns keep full context. Sessions are
/// persisted incrementally to the database and can be restored across app
/// restarts via [PromptOptimizerSession.fromStored].
class PromptOptimizerSession extends ChangeNotifier {
  static int _counter = 0;

  PromptOptimizerSession({this.mode = AssistantMode.systemPrompt, String? id})
      : id = id ?? 'opt_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';

  final String id;

  /// Session title shown in the history list (first user message, truncated).
  String? title;

  /// How many [history] messages are already persisted to the database.
  int persistedCount = 0;

  /// Fixed for the session's lifetime — switching modes starts a new
  /// conversation so the history semantics stay coherent.
  final AssistantMode mode;

  /// True when the session needs a validated knowledge base to run at all.
  /// Prefer this over comparing [mode] directly — the checks live in several
  /// files and an omitted one leaves the mode silently inert.
  bool get usesKnowledgeBase =>
      mode == AssistantMode.knowledgeBase || mode == AssistantMode.knowledgeEdit;

  /// True when the agent may propose knowledge-base edits.
  bool get canWriteKnowledge => mode == AssistantMode.knowledgeEdit;

  /// Chars-per-token measured from the last request the provider reported
  /// token usage for, or null while it has reported none.
  ///
  /// Lets the budget fit the user's actual content — English runs ~4
  /// chars/token, Chinese ~1–1.3, and a constant cannot serve both — while
  /// staying entirely optional: providers may omit usage, and then the
  /// conservative default applies.
  double? observedCharsPerToken;

  /// [history] length at the moment each knowledge file was last written, so
  /// reads recorded before the write stop counting as current.
  ///
  /// A plain "is stale" flag would be unsatisfiable: the read-before-write
  /// rail would reject the very re-read that is supposed to clear it, and the
  /// model could never edit the same file twice in one session.
  final Map<String, int> knowledgeStaleAt = {};

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

  void addUserTurn(String text) {
    history.add(LLMMessage(role: LLMRole.user, content: text));
    _addEntry(OptimizerChatEntry(kind: OptimizerEntryKind.user, text: text));
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

  /// Stages a proposed knowledge-file edit for the user to approve. Nothing
  /// touches disk here — same contract as [_stagePrompt].
  String _stageKbEdit({
    required String relPath,
    required String newContent,
    required String? oldContent,
    String? note,
  }) {
    final editId = 'kbedit_${id}_${_kbEditCounter++}';
    _addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.kbEdit,
      text: relPath,
      editId: editId,
      targetPath: relPath,
      newContent: newContent,
      oldContent: oldContent,
      editState: KbEditState.pending,
      note: (note == null || note.trim().isEmpty) ? null : note.trim(),
    ));
    return editId;
  }

  /// Flips a staged edit to its terminal state. Rebuilds the transcript rather
  /// than mutating the entry in place; because the length is unchanged, the
  /// chat view re-renders without yanking the user's scroll position.
  void _resolveKbEdit(String editId, KbEditState state) {
    _transcript = [
      for (final e in _transcript)
        (e.kind == OptimizerEntryKind.kbEdit && e.editId == editId)
            ? e.copyWith(editState: state)
            : e,
    ];
    notifyListeners();
  }

  @visibleForTesting
  String stageKbEditForTest({
    required String relPath,
    required String newContent,
    String? oldContent,
    String? note,
  }) =>
      _stageKbEdit(
        relPath: relPath,
        newContent: newContent,
        oldContent: oldContent,
        note: note,
      );

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

  void _setRunning(bool running) {
    if (_isRunning == running) return;
    _isRunning = running;
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
    session.history.addAll(history);
    session.persistedCount = history.length;

    final entries = <OptimizerChatEntry>[];
    if (hasCompactedHistory && compactedNoticeText != null) {
      entries.add(OptimizerChatEntry(kind: OptimizerEntryKind.notice, text: compactedNoticeText));
    }
    bool anyImageMissing = false;
    for (int msgIndex = 0; msgIndex < history.length; msgIndex++) {
      final msg = history[msgIndex];
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
            // Compaction summaries are context, not chat lines.
          } else {
            entries.add(OptimizerChatEntry(kind: OptimizerEntryKind.user, text: msg.content));
          }
        case LLMRole.assistant:
          if (msg.content.trim().isNotEmpty) {
            entries.add(OptimizerChatEntry(kind: OptimizerEntryKind.assistant, text: msg.content.trim()));
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
                  session.knowledgeStaleAt[writtenPath] = msgIndex;
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
                for (int j = msgIndex + 1; j < history.length; j++) {
                  final r = history[j];
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

  /// Transcript-notice tokens, mapped to localized strings at render time.
  static const String compactedNoticeToken = '__compacted__';
  static const String imageMissingNoticeToken = '__image_missing__';
  static const String kbEntryTooLargeNoticeToken = '__kb_entry_too_large__';

  /// Share of the window above which the system prompt is called out.
  ///
  /// Past half, a two-message conversation cannot fit — and unlike history, the
  /// system prompt is re-sent in full every request and compaction cannot touch
  /// it, so nothing downstream can rescue it.
  static const double _systemPromptWarnShare = 0.5;

  /// Memory management: the most recent user turns whose tool results and
  /// image attachments are never elided or compacted away.
  static const int _keepRecentTurns = 6;

  /// Layer-2 compaction's secondary trigger: raw message count, independent of
  /// size. A long conversation of short turns costs little context but still
  /// slows every request down.
  static const int _compactMaxMessages = 120;

  static const String retentionSettingKey = 'assistant_session_retention';
  static const int defaultRetention = 20;

  /// Fraction of the model's context window at which the conversation is
  /// summarized to make room ("hard summary limit").
  ///
  /// The headroom above it is not waste — it is what funds reading a knowledge
  /// file in one piece mid-turn, which compaction then reclaims at the next
  /// turn boundary. See [ContextBudget.readCapChars].
  static const String contextRatioSettingKey = 'assistant_context_ratio';
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

  /// Live sessions by id, so the task-queue executor can resolve the session
  /// referenced by a queued task.
  static final Map<String, PromptOptimizerSession> sessions = {};

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
  static int _readCapNow(
    PromptOptimizerSession session,
    String systemPrompt,
    int? contextWindow,
  ) =>
      ContextBudget.readCapChars(
        contextWindow,
        occupiedChars(systemPrompt, _trimForSend(session.history)),
        observedCharsPerToken: session.observedCharsPerToken,
      );

  static final List<LLMTool> _tools = [
    LLMTool(
      name: 'list_reference_images',
      description: 'List the reference images the user attached to this '
          'session. Returns a JSON array of {id, name, size_kb} objects.',
      parameters: {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    ),
    LLMTool(
      name: 'view_image',
      description: 'Look at one reference image, identified by its id from '
          'list_reference_images. The image is attached to the conversation '
          'right after this call. Call it once per image you need to see.',
      parameters: {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': 'The image id exactly as returned by list_reference_images.',
          },
        },
        'required': ['id'],
      },
    ),
    LLMTool(
      name: 'submit_prompt',
      description: 'Deliver an optimized prompt to the user. This is the ONLY '
          'way to deliver a result — never paste the final prompt as plain '
          'chat text. Call it again with a full revised prompt whenever the '
          'user asks for changes.',
      parameters: {
        'type': 'object',
        'properties': {
          'prompt': {
            'type': 'string',
            'description': 'The complete optimized prompt text.',
          },
          'note': {
            'type': 'string',
            'description': 'Optional one-sentence summary of what was changed or emphasized.',
          },
        },
        'required': ['prompt'],
      },
    ),
    LLMTool(
      name: 'ask_user',
      description: 'Ask the user 1-4 structured clarifying questions and STOP. '
          'The turn pauses until the user answers; their choices arrive as '
          'this tool\'s result. Use it only when ambiguity genuinely blocks '
          'the work — prefer it over guessing, but never ask what you can '
          'infer. Offer concrete options. Call it at most once per turn and '
          'do not combine it with other tool calls in the same message.',
      parameters: {
        'type': 'object',
        'properties': {
          'questions': {
            'type': 'array',
            'description': '1 to 4 questions.',
            'items': {
              'type': 'object',
              'properties': {
                'header': {
                  'type': 'string',
                  'description': 'Very short label (2-3 words) shown as the question title.',
                },
                'question': {
                  'type': 'string',
                  'description': 'The full question text.',
                },
                'multi_select': {
                  'type': 'boolean',
                  'description': 'Allow choosing several options. Default false.',
                },
                'options': {
                  'type': 'array',
                  'description': '2 to 4 concrete choices. The user can always add free text instead.',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'label': {'type': 'string', 'description': 'Short choice text.'},
                      'description': {
                        'type': 'string',
                        'description': 'Optional one-line explanation of this choice.',
                      },
                    },
                    'required': ['label'],
                  },
                },
              },
              'required': ['header', 'question', 'options'],
            },
          },
        },
        'required': ['questions'],
      },
    ),
  ];

  static final List<LLMTool> _knowledgeTools = [
    LLMTool(
      name: 'list_knowledge_files',
      description: 'List knowledge-base markdown files and subdirectories. '
          'Returns {files:[{path, size_kb, is_dir}]}. Pass "dir" (a relative '
          'path from a previous listing) to descend into a subdirectory.',
      parameters: {
        'type': 'object',
        'properties': {
          'dir': {
            'type': 'string',
            'description': 'Optional subdirectory (relative path). Omit for the root.',
          },
        },
      },
    ),
    LLMTool(
      name: 'read_knowledge_file',
      description: 'Read one knowledge file by its relative path. A file that '
          'fits the remaining context comes back whole (total_pages: 1); a '
          'larger one is split, and the result carries page/total_pages — '
          'request further pages only when you actually need them. How much '
          'fits depends on how full the conversation already is, so total_pages '
          'may differ between reads of the same file. Read selectively: '
          'list_knowledge_files reports size_kb, and loading rules you do not '
          'need costs context you will want later. Never re-read a page that is '
          'already in the conversation.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path exactly as shown by list_knowledge_files or the file map.',
          },
          'page': {
            'type': 'integer',
            'description': '1-based page number, defaults to 1.',
          },
        },
        'required': ['path'],
      },
    ),
  ];

  /// Write tools, added only in [AssistantMode.knowledgeEdit].
  ///
  /// Deliberately just one tool, and no delete: the mode's invariant is that it
  /// can only add or replace content, always behind a user-approved preview,
  /// and can never destroy data.
  static final List<LLMTool> _knowledgeWriteTools = [
    LLMTool(
      name: 'write_knowledge_file',
      description: 'Propose creating or rewriting one knowledge-base markdown '
          'file. The edit is STAGED for the user to review and approve — it is '
          'NOT written to disk by this call. You must pass the COMPLETE new '
          'file content (there is no patch/diff mode). Before rewriting an '
          'existing file you must read it first with read_knowledge_file. '
          'Whenever you add or rename a file, also update the entry file '
          '(README.md) so the file map keeps matching the real tree.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': 'Relative path from the knowledge base root. Must end in .md.',
          },
          'content': {
            'type': 'string',
            'description': 'The complete new content of the file, not a fragment or a diff.',
          },
          'note': {
            'type': 'string',
            'description': 'Optional one-sentence summary of what this edit changes and why.',
          },
        },
        'required': ['path', 'content'],
      },
    ),
  ];

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
    required List<Map<String, String>> referenceImages,
    bool forceViewAllImages = false,
    String? knowledgeRoot,
    String? knowledgeEntryContent,
    String? contextId,
    int? contextWindow,
    double contextRatio = defaultContextRatio,
    void Function(String message)? onLog,
    bool Function()? isCancelled,
  }) async {
    session._setRunning(true);
    final knowledgeMode = session.usesKnowledgeBase;
    final editMode = session.canWriteKnowledge;
    if (knowledgeMode && (knowledgeRoot == null || knowledgeEntryContent == null)) {
      session._setRunning(false);
      throw StateError('Knowledge mode requires knowledgeRoot and knowledgeEntryContent.');
    }
    final tools = editMode
        ? [..._tools, ..._knowledgeTools, ..._knowledgeWriteTools]
        : (knowledgeMode ? [..._tools, ..._knowledgeTools] : _tools);
    // Weak local models tend to issue a single tool call per turn, so viewing
    // every reference image one by one needs list + N views + submit turns.
    // Knowledge mode needs extra headroom for file listing/reading rounds.
    // Edit mode needs more still — not because writes are expensive, but
    // because the read-before-write rail forces a read round per file touched.
    final baseTurns = editMode ? 24 : (knowledgeMode ? 20 : _maxTurns);
    final minTurns = referenceImages.length + (knowledgeMode ? 8 : 4);
    final maxTurns = baseTurns > minTurns ? baseTurns : minTurns;
    final repo = AssistantSessionRepository();

    /// Set once a read finds no room left, for the rest of this turn.
    bool contextExhausted = false;

    // Built once: it is identical on every request of this turn, and both the
    // budget check and the request itself must see the same string — it is the
    // largest fixed cost in the window (the knowledge-base file map lives in
    // it) and is re-sent in full every single request.
    final systemPromptText = editMode
        ? _buildKnowledgeEditSystemPrompt(
            knowledgeEntryContent!, referenceImages.length, forceViewAllImages)
        : knowledgeMode
            ? _buildKnowledgeSystemPrompt(
                knowledgeEntryContent!, referenceImages.length, forceViewAllImages)
            : _buildSystemPrompt(systemPrompt, referenceImages.length, forceViewAllImages);

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
          text: kbEntryTooLargeNoticeToken,
        ));
      }
    }

    try {
      // Persist the pending user turn, then compact if the history has grown
      // past the context budget. Persistence failures never block the turn.
      try {
        await _syncPersistence(session, referenceImages, repo);
        await _maybeCompact(
          session,
          modelIdentifier,
          repo,
          contextId,
          onLog,
          systemPrompt: systemPromptText,
          contextWindow: contextWindow,
          contextRatio: contextRatio,
        );
      } catch (e) {
        onLog?.call('Session persistence failed (continuing without it): $e');
      }
      _cancelDanglingAskUser(session);
      for (int turn = 0; turn < maxTurns; turn++) {
        if (isCancelled?.call() ?? false) return;

        // Once there is no room to read, stop offering the tool at all. Left in
        // the list the model would keep calling it and keep being refused, and
        // each refusal costs another full-window request — the loop still has
        // its remaining iterations to burn. Without it the model can only
        // answer or submit, and the loop exits on its own.
        final activeTools = contextExhausted
            ? [for (final t in tools) if (t.name != 'read_knowledge_file') t]
            : tools;

        final trimmedHistory = _trimForSend(session.history);
        // knowledgeEntryContent is captured once per task, but staging means no
        // edit can reach disk mid-turn, so the injected file map cannot go
        // stale within a turn.
        final sentChars = occupiedChars(systemPromptText, trimmedHistory);

        final LLMResponse response;
        try {
          response = await LLMService().request(
            modelIdentifier: modelIdentifier,
            messages: [
              LLMMessage(role: LLMRole.system, content: systemPromptText),
              ...trimmedHistory,
            ],
            tools: activeTools,
            contextId: contextId,
            // Transient relay/proxy disconnects (e.g. errno 10054) should not
            // kill the whole agent turn — retry a couple of times.
            options: const {'retryCount': 2},
            useStream: false,
          );
        } catch (e) {
          session._addEntry(OptimizerChatEntry(
            kind: OptimizerEntryKind.error,
            text: e.toString(),
          ));
          rethrow;
        }

        // Calibrate against what this request actually cost. Providers may
        // report no usage at all, in which case observedCharsPerToken stays as
        // it was and the conservative default keeps applying.
        final observed = ContextBudget.calibrate(
          charsSent: sentChars,
          promptTokens: LLMService.promptTokensOf(response.metadata),
        );
        if (observed != null) session.observedCharsPerToken = observed;

        if (response.toolCalls.isEmpty) {
          // Model is done: plain text is a chat reply (comment, clarifying
          // question, ...), never the deliverable itself.
          final text = response.text.trim();
          if (text.isNotEmpty) {
            session.history.add(LLMMessage(role: LLMRole.assistant, content: text));
            session._addEntry(OptimizerChatEntry(kind: OptimizerEntryKind.assistant, text: text));
          }
          return;
        }

        // Echo the assistant turn (with its tool calls) back into history.
        session.history.add(LLMMessage(
          role: LLMRole.assistant,
          content: response.text,
          toolCalls: response.toolCalls,
        ));
        if (response.text.trim().isNotEmpty) {
          session._addEntry(OptimizerChatEntry(
            kind: OptimizerEntryKind.assistant,
            text: response.text.trim(),
          ));
        }

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
        // The ONE deliberate exception is a valid ask_user call: it stays
        // dangling and the turn returns, because its result IS the user's
        // answer. This is safe — nothing sends the history while it dangles
        // (the turn has ended), and every path back into a turn pairs it
        // first: answerAskUser, resolvePendingAskUserAsFreeText, or the
        // self-healing guard at the top of runTurn.
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
          } else if (call.name == 'ask_user') {
            if (pendingAskCallId != null) {
              result = {
                'status': 'error',
                'message': 'Only one ask_user call per turn — this one was '
                    'ignored. Fold extra questions into the pending call next time.',
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
                pendingAskCallId = call.id;
                continue; // Deliberately NO paired result — see comment above.
              }
            }
          } else {
            try {
              result = _executeTool(
                call,
                referenceImages,
                session,
                pendingViews,
                forceViewAllImages,
                knowledgeRoot,
                onLog,
                systemPrompt: systemPromptText,
                contextWindow: contextWindow,
                onContextExhausted: () => contextExhausted = true,
              );
            } catch (e) {
              onLog?.call('Tool ${call.name} failed: $e');
              result = {
                'status': 'error',
                'message': 'Tool ${call.name} failed: $e',
              };
            }
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
              LLMAttachment.fromFile(File(view['path']!), _mimeTypeFor(view['path']!)),
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
      onLog?.call('Reached the maximum of $maxTurns agent turns — stopping.');
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
        .where((m) =>
            m.role == LLMRole.user &&
            !m.content.startsWith(viewResultMarker) &&
            !m.content.startsWith(summaryMarker))
        .map((m) => m.content.trim())
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');
    final oneLine = first.replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length <= 40 ? oneLine : '${oneLine.substring(0, 40)}…';
  }

  /// Index of the user message that opens the protected "recent" window
  /// (the last [_keepRecentTurns] real user turns). 0 = protect everything.
  static int _recentBoundary(List<LLMMessage> history) {
    int userSeen = 0;
    for (int i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      if (m.role == LLMRole.user &&
          !m.content.startsWith(viewResultMarker) &&
          !m.content.startsWith(summaryMarker)) {
        userSeen++;
        if (userSeen >= _keepRecentTurns) return i;
      }
    }
    return 0;
  }

  /// Below this many chars a read is not worth doing: the model would get a
  /// fragment too small to reason from, and would likely just ask for the next
  /// one, burning a full-window request each time.
  static const int _minReadChars = 2000;

  /// Rough per-attachment char cost, standing in for an image's token price.
  ///
  /// An image carries no characters but is far from free — roughly 1–1.5K
  /// tokens for a 1024² image on Gemini. Counting it as zero (as the old
  /// threshold did) makes a session with reference images look emptier than it
  /// is, and over-grants the knowledge read budget by exactly that much.
  static const int _attachmentChars = 2000;

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
  static Set<int> _liveReadPages(PromptOptimizerSession session, String relPath) {
    final history = session.history;
    // Reads before the recent boundary are elided by _trimForSend; reads
    // before the file was last written no longer describe what is on disk.
    final boundary = _recentBoundary(history);
    final staleAt = session.knowledgeStaleAt[relPath] ?? 0;
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

  @visibleForTesting
  static Set<int> liveReadPagesForTest(PromptOptimizerSession session, String relPath) =>
      _liveReadPages(session, relPath);

  /// Layer-1 (lossless in DB, per-request) trimming: before the recent
  /// window, bulky knowledge-file tool results are elided and viewed-image
  /// attachments dropped. User/assistant text and submit_prompt results are
  /// always kept. Tool call/result pairing is preserved (only contents are
  /// shortened), which Gemini requires.
  static List<LLMMessage> _trimForSend(List<LLMMessage> history) {
    final boundary = _recentBoundary(history);
    if (boundary == 0) return history;
    return [
      for (int i = 0; i < history.length; i++)
        i >= boundary ? history[i] : _elide(history[i]),
    ];
  }

  static LLMMessage _elide(LLMMessage m) {
    if (m.role == LLMRole.tool &&
        m.toolName == 'read_knowledge_file' &&
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
    if (m.role == LLMRole.user &&
        m.content.startsWith(viewResultMarker) &&
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
    if (m.role == LLMRole.assistant &&
        m.toolCalls.any((c) =>
            c.name == 'write_knowledge_file' &&
            (c.arguments['content']?.toString().length ?? 0) > 300)) {
      return LLMMessage(
        role: LLMRole.assistant,
        content: m.content,
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
  /// a single summary message (LLM-generated; hard truncation as fallback).
  /// The database keeps the original rows flagged `compacted` and re-appends
  /// the new active history, so the full record stays inspectable.
  static Future<void> _maybeCompact(
    PromptOptimizerSession session,
    dynamic modelIdentifier,
    AssistantSessionRepository repo,
    String? contextId,
    void Function(String message)? onLog, {
    required String systemPrompt,
    required int? contextWindow,
    required double contextRatio,
  }) async {
    final trimmed = _trimForSend(session.history);
    final occupied = occupiedChars(systemPrompt, trimmed);
    final budget = ContextBudget.budgetChars(
      contextWindow,
      contextRatio,
      observedCharsPerToken: session.observedCharsPerToken,
    );
    if (!shouldCompact(
      occupied: occupied,
      budgetChars: budget,
      messageCount: session.history.length,
    )) {
      return;
    }
    final boundary = _recentBoundary(session.history);
    if (boundary <= 1) {
      // Nothing meaningful to fold. Worth saying out loud when it is the size
      // that triggered this: compaction only folds history, so it can never
      // shrink an oversized system prompt, and the request is about to fail
      // with nothing but the provider's own error to explain why.
      if (occupied >= budget) {
        onLog?.call('Context is over budget ($occupied/$budget chars) but there '
            'is nothing to summarize yet — the system prompt or the current '
            'turn alone exceeds the budget.');
      }
      return;
    }

    final head = session.history.sublist(0, boundary);
    onLog?.call('Context budget reached ($occupied/$budget chars, '
        '${(contextRatio * 100).round()}% of the window) — summarizing '
        '${head.length} early messages.');
    String summaryText;
    try {
      final response = await LLMService().request(
        modelIdentifier: modelIdentifier,
        messages: [
          LLMMessage(
            role: LLMRole.system,
            content: 'You compress a prompt-engineering conversation into a '
                'dense working summary. Keep, verbatim where possible: the '
                'user\'s core request and all confirmed design/character '
                'details; every knowledge-base file already consulted (paths '
                'only); the LATEST submitted prompt in full; unresolved '
                'questions. Discard tool chatter. Answer with the summary '
                'only.',
          ),
          LLMMessage(role: LLMRole.user, content: _serializeForSummary(head)),
        ],
        contextId: contextId,
        options: const {'retryCount': 2},
        useStream: false,
      );
      summaryText = response.text.trim();
      if (summaryText.isEmpty) throw Exception('empty summary');
    } catch (e) {
      onLog?.call('Summary generation failed ($e) — falling back to hard truncation.');
      summaryText = 'Earlier conversation was truncated to save context. '
          'Latest staged prompt (v${session.promptVersions}): '
          '${session.refinedPrompt ?? '(none yet)'}';
    }

    final summaryMsg = LLMMessage(role: LLMRole.user, content: '$summaryMarker\n$summaryText');
    final tail = session.history.sublist(boundary);
    session.history
      ..clear()
      ..addAll([summaryMsg, ...tail]);
    session.persistedCount = session.history.length;
    await repo.compactAll(session.id, session.history);
    session._addEntry(OptimizerChatEntry(
      kind: OptimizerEntryKind.notice,
      text: compactedNoticeToken,
    ));
  }

  /// Plain-text rendering of history for the summarization call. Tool results
  /// are clipped hard — the summary needs decisions, not raw file contents.
  static String _serializeForSummary(List<LLMMessage> messages) {
    final buffer = StringBuffer();
    for (final m in messages) {
      switch (m.role) {
        case LLMRole.user:
          if (m.content.startsWith(viewResultMarker)) continue;
          buffer.writeln('USER: ${m.content}');
        case LLMRole.assistant:
          if (m.content.trim().isNotEmpty) buffer.writeln('ASSISTANT: ${m.content.trim()}');
          for (final call in m.toolCalls) {
            if (call.name == 'submit_prompt') {
              buffer.writeln('SUBMITTED PROMPT: ${call.arguments['prompt'] ?? ''}');
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

  static Map<String, dynamic> _executeTool(
    LLMToolCall call,
    List<Map<String, String>> referenceImages,
    PromptOptimizerSession session,
    List<Map<String, String>> pendingViews,
    bool forceViewAllImages,
    String? knowledgeRoot,
    void Function(String message)? onLog, {
    required String systemPrompt,
    required int? contextWindow,
    required void Function() onContextExhausted,
  }) {
    switch (call.name) {
      case 'list_knowledge_files':
        if (knowledgeRoot == null) return _kbUnavailable();
        final dir = call.arguments['dir']?.toString();
        onLog?.call('Tool call: list_knowledge_files (${dir ?? '.'})');
        session._addEntry(OptimizerChatEntry(
          kind: OptimizerEntryKind.tool,
          text: dir ?? '',
          toolName: 'list_knowledge_files',
        ));
        try {
          final files = KnowledgeBaseService().listFiles(knowledgeRoot, dir: dir);
          return {'files': [for (final f in files) f.toJson()]};
        } on KbPathException catch (e) {
          return {'status': 'error', 'message': e.message};
        } catch (e) {
          // listSync/lengthSync throw FileSystemException when the folder
          // vanishes mid-session; surface it as a tool error instead of
          // letting it escape and unpair the tool-call batch.
          return {'status': 'error', 'message': 'Failed to list knowledge files: $e'};
        }

      case 'read_knowledge_file':
        if (knowledgeRoot == null) return _kbUnavailable();
        final relPath = call.arguments['path']?.toString() ?? '';
        final rawPage = call.arguments['page'];
        final page = rawPage is int ? rawPage : int.tryParse(rawPage?.toString() ?? '') ?? 1;
        onLog?.call('Tool call: read_knowledge_file $relPath (page $page)');
        if (_liveReadPages(session, relPath).contains(page)) {
          return {
            'status': 'ok',
            'note': 'This page is already in the conversation — refer to the earlier result instead of re-reading it.',
          };
        }
        final cap = _readCapNow(session, systemPrompt, contextWindow);
        if (cap < _minReadChars) {
          // Returning a sliver instead would be worse than refusing: the model
          // would keep asking for more, and every retry is another full-window
          // request. Nothing reclaims context mid-turn, so say so and take the
          // tool away rather than let the loop grind through its remaining
          // iterations.
          onContextExhausted();
          onLog?.call('Context exhausted (~$cap chars free) — knowledge reading '
              'disabled for the rest of this turn.');
          return {
            'status': 'error',
            'message': 'Not enough context left to read more of the knowledge '
                'base. Work with what you have already read, or tell the user '
                'to start a new conversation for a fresh context.',
          };
        }
        try {
          final result = KnowledgeBaseService()
              .readFile(knowledgeRoot, relPath, page: page, maxChars: cap);
          session._addEntry(OptimizerChatEntry(
            kind: OptimizerEntryKind.tool,
            text: result.totalPages > 1 ? '$relPath (${result.page}/${result.totalPages})' : relPath,
            toolName: 'read_knowledge_file',
          ));
          return {
            'path': relPath,
            'page': result.page,
            'total_pages': result.totalPages,
            'content': result.content,
            if (result.totalPages > result.page)
              'note': 'File continues — request the next page only if this part is not enough.',
          };
        } on KbPathException catch (e) {
          return {'status': 'error', 'message': e.message};
        } catch (e) {
          return {'status': 'error', 'message': 'Failed to read $relPath: $e'};
        }
      case 'write_knowledge_file':
        if (knowledgeRoot == null) return _kbUnavailable();
        // The tool is only registered in edit mode, but a model can hallucinate
        // a tool name it was never offered — the mode, not the tool list, is
        // what decides whether this session may propose edits at all.
        if (!session.canWriteKnowledge) {
          return {
            'status': 'error',
            'message': 'This session is read-only. Knowledge files can only be '
                'edited in the knowledge-base maintenance mode.',
          };
        }
        final writePath = call.arguments['path']?.toString() ?? '';
        final writeContent = call.arguments['content']?.toString() ?? '';
        onLog?.call('Tool call: write_knowledge_file $writePath (${writeContent.length} chars)');
        if (writePath.trim().isEmpty) {
          return {'status': 'error', 'message': 'The path argument must not be empty.'};
        }
        if (writeContent.isEmpty) {
          return {
            'status': 'error',
            'message': 'The content argument must not be empty. Pass the complete file content.',
          };
        }
        try {
          final kb = KnowledgeBaseService();
          final existing = kb.readFullFile(knowledgeRoot, writePath);
          // Read-before-write rail, enforced here rather than left to the
          // system prompt: overwriting a file the model has not read is the
          // cheapest way for it to silently destroy the user's rules. Keyed on
          // a *live* read, so a read that has since been elided or compacted
          // away no longer licenses a write — the model must fetch the file
          // again and diff against what it can actually see.
          if (existing != null && _liveReadPages(session, writePath).isEmpty) {
            return {
              'status': 'error',
              'message': 'Read $writePath with read_knowledge_file first — you '
                  'must not overwrite a file you have not read.',
            };
          }
          session._stageKbEdit(
            relPath: writePath,
            newContent: writeContent,
            oldContent: existing,
            note: call.arguments['note']?.toString(),
          );
          return {
            'status': 'ok',
            'message': 'Edit to $writePath staged for user approval. It is NOT '
                'written yet — do not assume it was applied, and do not re-read '
                'the file expecting your new content.',
          };
        } on KbPathException catch (e) {
          return {'status': 'error', 'message': e.message};
        } catch (e) {
          return {'status': 'error', 'message': 'Failed to stage edit for $writePath: $e'};
        }

      case 'list_reference_images':
        onLog?.call('Tool call: list_reference_images (${referenceImages.length} images)');
        session._addEntry(OptimizerChatEntry(
          kind: OptimizerEntryKind.tool,
          text: '',
          toolName: 'list_reference_images',
        ));
        if (referenceImages.isEmpty) {
          return {'images': [], 'note': 'The user attached no reference images.'};
        }
        return {
          'images': [
            for (int i = 0; i < referenceImages.length; i++)
              {
                'id': i + 1,
                'name': referenceImages[i]['name'],
                'size_kb': _fileSizeKb(referenceImages[i]['path']),
              }
          ],
        };

      case 'view_image':
        // Accept both a JSON number and a numeric string — smaller models
        // often quote integer arguments.
        final rawId = call.arguments['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        if (id == null || id < 1 || id > referenceImages.length) {
          onLog?.call('Tool call rejected: unknown image id "$rawId"');
          return {
            'status': 'error',
            'message': 'Unknown id. Use an id exactly as returned by '
                'list_reference_images (1..${referenceImages.length}).',
          };
        }
        final image = referenceImages[id - 1];
        final path = image['path']!;
        onLog?.call('Tool call: view_image #$id (${image['name']})');
        final alreadyAttached = pendingViews.any((v) => v['path'] == path);
        if (session.viewedImagePaths.contains(path) || alreadyAttached) {
          return {
            'status': 'ok',
            'note': 'Image #$id was already attached earlier in this '
                'conversation — refer to that attachment.',
          };
        }
        if (!File(path).existsSync()) {
          return {
            'status': 'error',
            'message': 'Image #$id no longer exists on disk.',
          };
        }
        pendingViews.add({'id': '$id', 'name': image['name'] ?? '', 'path': path});
        session._markViewed(path);
        session._addEntry(OptimizerChatEntry(
          kind: OptimizerEntryKind.tool,
          text: image['name'] ?? '',
          toolName: 'view_image',
        ));
        final unviewed = [
          for (int i = 0; i < referenceImages.length; i++)
            if (!session.viewedImagePaths.contains(referenceImages[i]['path']))
              i + 1,
        ];
        return {
          'status': 'ok',
          'note': 'Image #$id is attached in the next message.',
          if (forceViewAllImages && unviewed.isNotEmpty)
            'reminder': 'Still unviewed image ids: ${unviewed.join(', ')}. '
                'View them all before calling submit_prompt.',
        };

      case 'submit_prompt':
        final prompt = call.arguments['prompt']?.toString() ?? '';
        if (prompt.trim().isEmpty) {
          return {
            'status': 'error',
            'message': 'The prompt argument must not be empty.',
          };
        }
        onLog?.call('Tool call: submit_prompt (v${session.promptVersions + 1}, ${prompt.length} chars)');
        session._stagePrompt(prompt, call.arguments['note']?.toString());
        return {
          'status': 'ok',
          'message': 'Prompt v${session.promptVersions} staged and shown to the user.',
        };

      default:
        return {
          'status': 'error',
          'message': 'Unknown tool "${call.name}". Available tools: '
              'list_reference_images, view_image, submit_prompt, ask_user'
              '${knowledgeRoot != null ? ', list_knowledge_files, read_knowledge_file' : ''}'
              '${session.canWriteKnowledge ? ', write_knowledge_file' : ''}.',
        };
    }
  }

  static Map<String, dynamic> _kbUnavailable() => {
        'status': 'error',
        'message': 'The knowledge base is not available in this session.',
      };

  /// Writes a staged edit to disk after the user approved it, and flips the
  /// transcript card to its terminal state. This is the only path that mutates
  /// the knowledge base — the agent never writes directly.
  static Future<void> applyStagedKbEdit({
    required PromptOptimizerSession session,
    required String editId,
  }) async {
    final entry = session._findKbEdit(editId);
    if (entry == null || entry.editState != KbEditState.pending) return;
    final relPath = entry.targetPath!;
    try {
      final root = await KnowledgeBaseService().getRoot();
      if (root == null) throw KbPathException('The knowledge base folder is not configured.');
      await KnowledgeBaseService().writeFile(root, relPath, entry.newContent!);
      // The file changed, so every read of it recorded so far describes content
      // that no longer exists — and page boundaries move on a rewrite, so
      // invalidating single pages would be meaningless. Marking the point in
      // history rather than dropping a flag keeps the re-read that follows
      // able to satisfy the read-before-write rail again.
      session.knowledgeStaleAt[relPath] = session.history.length;
      session._resolveKbEdit(editId, KbEditState.applied);
    } catch (_) {
      session._resolveKbEdit(editId, KbEditState.failed);
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

  /// Self-healing guard, run at the top of every turn: a dangling ask_user
  /// call must never reach a provider (both endpoints reject an unpaired tool
  /// call). The normal paths pair it before enqueueing a turn — the answer
  /// card via [answerAskUser], or free text via
  /// [resolvePendingAskUserAsFreeText] — so a turn starting while one is still
  /// pending means some other path got here (e.g. Retry on an old error).
  /// Cancel the question so the history is valid again.
  static void _cancelDanglingAskUser(PromptOptimizerSession session) {
    final dangling = session.pendingAskUser;
    if (dangling == null) return;
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({
        'status': 'cancelled',
        'message': 'The question was not answered.',
      }),
      toolCallId: dangling.callId,
      toolName: 'ask_user',
    ));
    session._resolveAskUser(dangling.callId, AskUserState.dismissed);
  }

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
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({
        'status': 'ok',
        'answers': [for (final a in answers) a.toJson()],
      }),
      toolCallId: callId,
      toolName: 'ask_user',
    ));
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
    session.history.add(LLMMessage(
      role: LLMRole.tool,
      content: jsonEncode({
        'status': 'ok',
        'note': 'The user replied in free text instead of choosing options — '
            'see the user message that follows.',
      }),
      toolCallId: callId,
      toolName: 'ask_user',
    ));
    session._resolveAskUser(callId, AskUserState.dismissed);
  }

  static String _buildSystemPrompt(
    String? template,
    int referenceImageCount,
    bool forceViewAllImages,
  ) {
    final base = (template == null || template.trim().isEmpty)
        ? 'You are an expert prompt engineer for AI image and video generation.'
        : template.trim();
    // Per-model setting: smaller local models look at one image and submit
    // straight away, so viewing every image can be made a hard requirement.
    final viewStep = forceViewAllImages && referenceImageCount > 0
        ? '1. MANDATORY: first call list_reference_images, then call '
            'view_image for EVERY image id from 1 to $referenceImageCount, '
            'one call per image. You must have viewed ALL '
            '$referenceImageCount reference image(s) before calling '
            'submit_prompt — never skip an image and never submit early.\n'
        : '1. If reference images could be relevant, inspect them with '
            'list_reference_images and view_image first.\n';
    return '$base\n\n'
        '---\n'
        'You are working inside an interactive prompt-optimization chat. The '
        'user gives you a rough idea or an existing prompt and you produce a '
        'refined, high-quality prompt. There are currently '
        '$referenceImageCount reference image(s) available.\n'
        'Tools:\n'
        '- list_reference_images: list the attached reference images.\n'
        '- view_image: look at one reference image before relying on it.\n'
        '- submit_prompt: deliver an optimized prompt. This is the ONLY way to '
        'deliver a result — never paste the final prompt as plain chat text.\n'
        '- ask_user: ask up to 4 structured questions with concrete options.\n'
        'Workflow:\n'
        '$viewStep'
        '2. Call submit_prompt with the complete optimized prompt (plus a '
        'short note describing what you changed).\n'
        '3. When the request is too ambiguous to optimize, ask via ask_user '
        '(structured options, at most once per turn) instead of a plain-text '
        'question — but never ask about details you can reasonably infer. '
        'Afterwards you may also reply with a brief comment.\n'
        'The user may reply with follow-up adjustments — deliver every '
        'revision through submit_prompt again, always with the full prompt.';
  }

  /// System prompt for [AssistantMode.knowledgeBase]. Built-in — user presets
  /// do not apply in this mode. The knowledge base entry file (the file map)
  /// is injected in full so the model can route to the right rule files
  /// without an extra discovery round; everything else is read on demand.
  static String _buildKnowledgeSystemPrompt(
    String entryContent,
    int referenceImageCount,
    bool forceViewAllImages,
  ) {
    final viewStep = forceViewAllImages && referenceImageCount > 0
        ? '- MANDATORY: call list_reference_images, then view_image for EVERY '
            'image id from 1 to $referenceImageCount before calling '
            'submit_prompt — never skip an image and never submit early.\n'
        : '- If reference images could be relevant, inspect them with '
            'list_reference_images and view_image before relying on them.\n';
    return 'You are a prompt-engineering agent for AI image generation. You '
        'build and refine prompts strictly according to the user\'s knowledge '
        'base — a folder of rule files whose entry file (the file map) is '
        'included below. The knowledge base is the user\'s own: its layout and '
        'vocabulary are theirs, and the file map is the only authority on how '
        'to navigate it.\n\n'
        '=== KNOWLEDGE BASE ENTRY (file map) ===\n'
        '$entryContent\n'
        '=== END OF ENTRY ===\n\n'
        'Tools:\n'
        '- list_knowledge_files / read_knowledge_file: browse and read '
        'knowledge files on demand.\n'
        '- list_reference_images / view_image: inspect the user\'s reference '
        'images ($referenceImageCount available).\n'
        '- submit_prompt: deliver a prompt. This is the ONLY way to deliver a '
        'result — never paste the final prompt as plain chat text.\n'
        '- ask_user: ask up to 4 structured questions with concrete options.\n'
        'Workflow:\n'
        '1. Route with the file map: read ONLY the files it points you to for '
        'this request, plus any whose stated condition the request meets, plus '
        'any it marks as always applying. Do NOT sweep the whole knowledge '
        'base. If the map points nowhere, the map itself is the rules.\n'
        '$viewStep'
        '2. Follow the structure the file map and the files you read '
        'prescribe — never invent your own, and never fabricate '
        'character/design details the user or the references did not provide.\n'
        '3. Deliver via submit_prompt (with a short note on choices made). '
        'When the request is too ambiguous to proceed, ask via ask_user '
        '(structured options, at most once per turn) instead of a plain-text '
        'question — but never ask about details the knowledge base or the '
        'references already settle.\n'
        'The user may reply with follow-up adjustments — apply the knowledge '
        'base rules again and deliver every revision through submit_prompt '
        'with the full prompt.';
  }

  /// System prompt for [AssistantMode.knowledgeEdit]. Built-in like the
  /// knowledge-base prompt; user presets do not apply. The deliverable here is
  /// a knowledge-base edit rather than a prompt, so the workflow leads with
  /// write_knowledge_file instead of submit_prompt.
  static String _buildKnowledgeEditSystemPrompt(
    String entryContent,
    int referenceImageCount,
    bool forceViewAllImages,
  ) {
    final viewStep = forceViewAllImages && referenceImageCount > 0
        ? '- MANDATORY: call list_reference_images, then view_image for EVERY '
            'image id from 1 to $referenceImageCount before calling '
            'submit_prompt — never skip an image and never submit early.\n'
        : '- If reference images could be relevant, inspect them with '
            'list_reference_images and view_image before relying on them.\n';
    return 'You are a knowledge-base maintainer for a prompt-engineering '
        'knowledge base — a folder of rule files whose entry file (the file '
        'map) is included below. You help the user improve and extend these '
        'files. The knowledge base is the user\'s own: its layout and '
        'vocabulary are theirs to choose, so work within the conventions the '
        'file map already establishes rather than imposing new ones.\n\n'
        '=== KNOWLEDGE BASE ENTRY (file map) ===\n'
        '$entryContent\n'
        '=== END OF ENTRY ===\n\n'
        'Tools:\n'
        '- list_knowledge_files / read_knowledge_file: browse and read '
        'knowledge files on demand.\n'
        '- write_knowledge_file: propose creating or rewriting one file. This '
        'is how you deliver changes.\n'
        '- list_reference_images / view_image: inspect the user\'s reference '
        'images ($referenceImageCount available).\n'
        '- submit_prompt: only if the user also asks for an actual prompt.\n'
        '- ask_user: ask up to 4 structured questions with concrete options — '
        'use it (at most once per turn) when the request is too ambiguous to '
        'proceed, instead of a plain-text question.\n'
        'Workflow:\n'
        '1. Use the file map to locate the files the request concerns, and read '
        'them. Read only what you need — do NOT sweep the whole knowledge base.\n'
        '2. You MUST read an existing file before rewriting it. Pass the '
        'COMPLETE new content to write_knowledge_file — there is no patch mode, '
        'and partial content would truncate the file.\n'
        '3. Preserve what the user already wrote. Improve structure and add '
        'what was asked for; do not silently drop existing rules, and never '
        'invent rules the user did not ask for.\n'
        '4. When you add, rename, or repurpose a file, update the entry file '
        '(${KnowledgeBaseService.entryFileName}) in the same turn so the file '
        'map keeps matching the real tree — a file missing from the map is '
        'invisible to the assistant. Follow whatever structure and wording the '
        'entry file already uses; the knowledge base is the user\'s own and its '
        'layout is theirs to choose.\n'
        '$viewStep'
        'Every edit is STAGED and shown to the user for approval — nothing you '
        'write reaches disk until they accept it. So never claim a change has '
        'been saved, and do not re-read a file expecting to find your own '
        'pending edit. After staging, briefly tell the user what you changed.';
  }

  static int _fileSizeKb(String? path) {
    if (path == null) return 0;
    try {
      return (File(path).lengthSync() / 1024).round();
    } catch (_) {
      return 0;
    }
  }

  static String _mimeTypeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return 'image/png';
    if (ext == '.webp') return 'image/webp';
    if (ext == '.gif') return 'image/gif';
    return 'image/jpeg';
  }
}
