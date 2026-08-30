import '../models/task_item.dart';
import 'prompt_optimizer_agent.dart';

/// Generation-task → prompt-version provenance.
///
/// Closes the gap the knowledge-optimization loop shipped with: a generated
/// image knew nothing about which assistant prompt version produced it, so
/// the gallery could not badge results and feedback could only bind to the
/// *latest* version. The chain is three hand-offs, each derived or carried by
/// data that already persists — nothing new is stored on its own:
///
///  1. Applying a prompt from the assistant records an
///     [AppliedAssistantPrompt] (in memory, on AppState — see the class doc
///     for why that is enough).
///  2. Task submission asks [AppliedAssistantPrompt.taskParamsFor] whether the
///     outgoing prompt is still that exact text; if so the task's persisted
///     `parameters` gain the session id and version.
///  3. The gallery badge and the feedback dialog derive a
///     `path → version` map from the tasks table
///     ([resultVersionsFromTasks]), which already persists `parameters` and
///     `result_path` — so provenance of completed generations survives
///     restarts for free.
class PromptProvenance {
  PromptProvenance._();

  /// Task-parameter keys the provenance travels under. String values only —
  /// `parameters` round-trips through JSON into SQLite.
  static const String sessionParamKey = 'assistantSessionId';
  static const String versionParamKey = 'assistantPromptVersion';

  /// The version number of [text] within [transcript], or null when no staged
  /// prompt matches.
  ///
  /// Matched by exact (trimmed) text rather than "the latest version":
  /// the transcript's prompt cards each carry an apply button, so the user
  /// can legitimately apply v2 after v3 exists — the version that reaches
  /// the workbench is whichever card they pressed. The scan runs backwards
  /// so a resubmitted identical text credits the newest version bearing it.
  static int? versionForPromptText(List<OptimizerChatEntry> transcript, String text) {
    final wanted = text.trim();
    if (wanted.isEmpty) return null;
    for (var i = transcript.length - 1; i >= 0; i--) {
      final e = transcript[i];
      if (e.kind != OptimizerEntryKind.prompt) continue;
      if (e.text.trim() == wanted) return e.version;
    }
    return null;
  }

  /// Projects [tasks] into a `result path → version` map for [sessionId].
  ///
  /// The repository's LIKE query is only a prefilter; this re-checks the
  /// decoded parameters, so callers may also feed it the live queue
  /// unfiltered. Later tasks win on a path collision (a regenerated file
  /// overwrites its predecessor on disk too).
  static Map<String, int> resultVersionsFromTasks(
    Iterable<TaskItem> tasks,
    String sessionId,
  ) {
    final versions = <String, int>{};
    for (final task in tasks) {
      if (task.parameters[sessionParamKey] != sessionId) continue;
      final version = _decodeVersion(task.parameters[versionParamKey]);
      if (version == null) continue;
      for (final path in task.resultPaths) {
        versions[path] = version;
      }
    }
    return versions;
  }

  /// Reads the version a task's parameters carry, or null when absent or
  /// malformed. Tolerant of the string form — parameters have been through
  /// JSON and, on old rows, through hand edits.
  static int? decodeVersionParam(Map<String, dynamic> parameters) =>
      _decodeVersion(parameters[versionParamKey]);

  static int? _decodeVersion(Object? raw) =>
      raw is int ? raw : int.tryParse(raw?.toString() ?? '');
}

/// The prompt most recently applied from the assistant to the workbench:
/// which session and version it was, and the exact text it had.
///
/// Deliberately in-memory only. The *applied-but-not-yet-generated* state is
/// a moment inside one sitting; everything after generation persists through
/// the tasks table. Persisting this record too would let a days-old "applied
/// v3" silently tag a generation the user no longer associates with the
/// assistant at all.
class AppliedAssistantPrompt {
  final String sessionId;
  final int version;
  final String text;

  const AppliedAssistantPrompt({
    required this.sessionId,
    required this.version,
    required this.text,
  });

  /// The provenance parameters for a generation about to run with [prompt],
  /// or null when the text no longer matches — an edited prompt is the
  /// user's own, and tagging it vN would claim a lineage it broke.
  Map<String, dynamic>? taskParamsFor(String prompt) {
    if (prompt.trim() != text.trim() || prompt.trim().isEmpty) return null;
    return {
      PromptProvenance.sessionParamKey: sessionId,
      PromptProvenance.versionParamKey: version,
    };
  }
}
