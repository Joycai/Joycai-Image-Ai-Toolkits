part of 'prompt_optimizer_agent.dart';

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

/// Which part of a file a staged knowledge-base edit targeted — what the
/// preview card names above its diff, so a hunk in a long file says where
/// it is.
enum KbEditScope {
  /// The whole file was sent (`replace_file`) — or a create.
  file,

  /// One section was replaced (`replace_section`).
  replaceSection,

  /// Text was added at the end of a section, or of the file (`append`).
  append,
}

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
///
/// [resultFeedback] is a user turn reporting the outcome of generating with a
/// staged prompt version (the feedback text plus which version and result
/// image it concerns). [kbDistill] marks the user's request to distill the
/// session's lessons into the knowledge base.
enum OptimizerEntryKind {
  user,
  assistant,
  tool,
  prompt,
  error,
  notice,
  kbEdit,
  askUser,
  resultFeedback,
  kbDistill,
}

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

  /// For [OptimizerEntryKind.kbEdit]: which part of the file was sent.
  final KbEditScope editScope;

  /// For [OptimizerEntryKind.kbEdit]: the heading line the section modes
  /// targeted, as the model spelled it; null for the whole file and for an
  /// append at the end of the file.
  final String? editSection;

  /// For [OptimizerEntryKind.kbEdit]: the knowledge-base root the edit was
  /// staged against. Apply writes there rather than re-reading the setting,
  /// which can be switched while the card waits.
  final String? knowledgeRoot;

  /// For [OptimizerEntryKind.kbEdit]: why a [KbEditState.failed] edit was not
  /// written.
  final String? editError;

  /// For [OptimizerEntryKind.askUser]: the tool-call id this card must answer.
  final String? askCallId;

  /// For [OptimizerEntryKind.askUser]: the structured questions.
  final List<AskUserQuestion>? askQuestions;

  /// For [OptimizerEntryKind.askUser]: lifecycle state of the card.
  final AskUserState? askState;

  /// For [OptimizerEntryKind.askUser]: the answers, once given (for the
  /// collapsed "answered" rendering).
  final List<AskUserAnswer>? askAnswers;

  /// For [OptimizerEntryKind.resultFeedback]: the thumbs up/down (`3b`), or
  /// null for a report written before ratings existed.
  final bool? feedbackSatisfied;

  /// For [OptimizerEntryKind.resultFeedback]: the reason tags behind a
  /// thumbs down; empty for a thumbs up or an untagged report.
  final List<ResultFeedbackReason> feedbackReasons;

  /// For [OptimizerEntryKind.assistant]: the reply hit the model's output
  /// limit and ends where the host cut it, not where the model stopped. The
  /// chat line says so at its tail and points at the model's max-output
  /// setting. Survives a restart through [LLMMessage.truncated].
  final bool truncated;

  /// For [OptimizerEntryKind.assistant]: this reply is the turn's answer —
  /// an analysis preset's result (`A3e`) — rather than a remark, so it is the
  /// one offered for copying. Survives a restart through
  /// [LLMMessage.deliverable].
  final bool deliverable;

  /// The model row (`llm_models.id`) whose reply this entry records, when
  /// the turn ran on a stored model. A cut reply's card jumps to *that*
  /// model's editor — the picker may have moved on by the time the user
  /// clicks. Survives a restart through [LLMMessage.modelDbId].
  final int? modelDbId;

  OptimizerChatEntry({
    required this.kind,
    required this.text,
    this.truncated = false,
    this.deliverable = false,
    this.modelDbId,
    this.version,
    this.note,
    this.feedbackSatisfied,
    this.feedbackReasons = const [],
    this.toolName,
    this.editId,
    this.targetPath,
    this.newContent,
    this.oldContent,
    this.editState,
    this.editScope = KbEditScope.file,
    this.editSection,
    this.knowledgeRoot,
    this.editError,
    this.askCallId,
    this.askQuestions,
    this.askState,
    this.askAnswers,
  });

  OptimizerChatEntry copyWith({
    KbEditState? editState,
    String? editError,
    AskUserState? askState,
    List<AskUserAnswer>? askAnswers,
    int? modelDbId,
  }) =>
      OptimizerChatEntry(
        kind: kind,
        text: text,
        truncated: truncated,
        modelDbId: modelDbId ?? this.modelDbId,
        version: version,
        note: note,
        feedbackSatisfied: feedbackSatisfied,
        feedbackReasons: feedbackReasons,
        toolName: toolName,
        editId: editId,
        targetPath: targetPath,
        newContent: newContent,
        oldContent: oldContent,
        editState: editState ?? this.editState,
        editScope: editScope,
        editSection: editSection,
        knowledgeRoot: knowledgeRoot,
        editError: editError ?? this.editError,
        askCallId: askCallId,
        askQuestions: askQuestions,
        askState: askState ?? this.askState,
        askAnswers: askAnswers ?? this.askAnswers,
      );
}
