import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'llm/llm_service.dart';
import 'llm/llm_types.dart';

/// A single rename suggestion collected from the model via tool calls.
class RenameProposal {
  final String path;
  final String oldName;
  final String newName;

  RenameProposal({required this.path, required this.oldName, required this.newName});
}

/// Runs the AI batch-rename flow as a standard LLM tool-use agent loop.
///
/// The model is given two tools:
///  * `list_files`   — reads the candidate files (id / name / category).
///  * `rename_file`  — proposes a new name for one file, addressed by id.
///
/// Files are addressed by a numeric id rather than their full path: paths
/// (especially Windows UNC ones) get mangled by JSON backslash escaping in
/// smaller models' tool calls, which made exact-path matching fail in loops.
///
/// `rename_file` is a dry-run: proposals are collected and validated but the
/// filesystem is never touched here. Callers decide when (and whether) to
/// apply them — the dialog shows a preview for user confirmation, the task
/// queue applies them at the end of the task.
class AiRenameAgent {
  static const int _maxTurns = 16;

  /// Files are fed to the model in chunks of this size. Small local models
  /// choke when dozens of files land in one context: they truncate the list,
  /// hallucinate ids, or blow the token budget mid-loop.
  static const int defaultBatchSize = 10;

  static final List<LLMTool> _tools = [
    LLMTool(
      name: 'list_files',
      description: 'List the files selected for renaming. Returns a JSON array of '
          '{id, name, category} objects.',
      parameters: {
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    ),
    LLMTool(
      name: 'rename_file',
      description: 'Propose a new file name for one file, identified by its id '
          'from list_files. The rename is staged, not applied immediately. Call '
          'this once per file that should be renamed. Keep the original file '
          'extension unless instructed otherwise.',
      parameters: {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': 'The file id exactly as returned by list_files.',
          },
          'new_name': {
            'type': 'string',
            'description': 'The new file name (name only, no directory separators).',
          },
        },
        'required': ['id', 'new_name'],
      },
    ),
  ];

  /// Runs the agent flow and returns the collected proposals.
  ///
  /// [filesData] entries must contain `original_name`, `path` and `category`.
  ///
  /// Files are processed in batches of [batchSize]: each batch gets its own
  /// fresh agent conversation so the model never sees more files than it can
  /// reliably handle in one context. Proposals accumulate across batches, and
  /// duplicate-target detection spans all batches. [onBatchProgress] reports
  /// (completedBatches, totalBatches) before each batch starts.
  static Future<List<RenameProposal>> collectProposals({
    required dynamic modelIdentifier,
    required List<Map<String, String>> filesData,
    String? systemPrompt,
    String? instructions,
    String? contextId,
    int batchSize = defaultBatchSize,
    void Function(String message)? onLog,
    void Function(int current, int total)? onBatchProgress,
    bool Function()? isCancelled,
  }) async {
    // path → proposal (a later call for the same path overrides the earlier one).
    final Map<String, RenameProposal> proposals = {};
    if (filesData.isEmpty) return [];

    final effectiveBatchSize = batchSize < 1 ? defaultBatchSize : batchSize;
    final totalBatches = (filesData.length / effectiveBatchSize).ceil();
    int consecutiveFailures = 0;

    for (int batch = 0; batch < totalBatches; batch++) {
      if (isCancelled?.call() ?? false) break;

      final start = batch * effectiveBatchSize;
      final chunk = filesData.sublist(
        start,
        (start + effectiveBatchSize).clamp(0, filesData.length),
      );
      onBatchProgress?.call(batch + 1, totalBatches);
      if (totalBatches > 1) {
        onLog?.call('Batch ${batch + 1}/$totalBatches: ${chunk.length} file(s) '
            '(${start + 1}-${start + chunk.length} of ${filesData.length}).');
      }

      try {
        await _runBatch(
          modelIdentifier: modelIdentifier,
          chunk: chunk,
          proposals: proposals,
          systemPrompt: systemPrompt,
          instructions: instructions,
          contextId: contextId,
          onLog: onLog,
          isCancelled: isCancelled,
        );
        consecutiveFailures = 0;
      } catch (e) {
        // Nothing staged at all and the very first batch died — the model or
        // server is likely misconfigured; surface the error to the caller.
        if (proposals.isEmpty && batch == 0) rethrow;
        consecutiveFailures++;
        onLog?.call('Batch ${batch + 1}/$totalBatches failed: $e — '
            'keeping the ${proposals.length} rename(s) staged so far.');
        if (consecutiveFailures >= 2) {
          onLog?.call('Two consecutive batches failed — stopping early.');
          break;
        }
      }
    }

    return proposals.values.toList();
  }

  /// One self-contained agent conversation over [chunk], staging results
  /// into the shared [proposals] map. Throws on provider errors.
  static Future<void> _runBatch({
    required dynamic modelIdentifier,
    required List<Map<String, String>> chunk,
    required Map<String, RenameProposal> proposals,
    String? systemPrompt,
    String? instructions,
    String? contextId,
    void Function(String message)? onLog,
    bool Function()? isCancelled,
  }) async {
    final messages = <LLMMessage>[
      LLMMessage(
        role: LLMRole.system,
        content: _buildSystemPrompt(systemPrompt),
      ),
      LLMMessage(
        role: LLMRole.user,
        content: 'User instructions: '
            '${(instructions == null || instructions.trim().isEmpty) ? "No additional instructions." : instructions.trim()}\n\n'
            'There are ${chunk.length} file(s) selected. '
            'Use the list_files tool to read them, then stage a rename for each file with the rename_file tool.',
      ),
    ];

    for (int turn = 0; turn < _maxTurns; turn++) {
      if (isCancelled?.call() ?? false) return;

      final response = await LLMService().request(
        modelIdentifier: modelIdentifier,
        messages: messages,
        tools: _tools,
        contextId: contextId,
        useStream: false,
      );

      if (response.toolCalls.isEmpty) {
        // Model is done (or answered in plain text).
        if (response.text.isNotEmpty) onLog?.call('AI: ${response.text}');
        return;
      }

      // Echo the assistant turn (with its tool calls) back into history.
      messages.add(LLMMessage(
        role: LLMRole.assistant,
        content: response.text,
        toolCalls: response.toolCalls,
      ));

      for (final call in response.toolCalls) {
        if (isCancelled?.call() ?? false) return;

        final result = _executeTool(call, chunk, proposals, onLog);
        messages.add(LLMMessage(
          role: LLMRole.tool,
          content: jsonEncode(result),
          toolCallId: call.id,
          toolName: call.name,
        ));
      }
    }
  }

  /// Applies proposals to disk. Returns the number of files actually renamed.
  static Future<int> applyProposals(
    List<RenameProposal> proposals, {
    void Function(String message)? onLog,
  }) async {
    int renamed = 0;
    for (final proposal in proposals) {
      final oldFile = File(proposal.path);
      final newPath = p.join(p.dirname(proposal.path), proposal.newName);
      if (proposal.newName == proposal.oldName) continue;
      if (await oldFile.exists()) {
        if (await File(newPath).exists()) {
          onLog?.call('Skipped (target exists): ${proposal.newName}');
          continue;
        }
        await oldFile.rename(newPath);
        renamed++;
        onLog?.call('Renamed: ${proposal.oldName} -> ${proposal.newName}');
      } else {
        onLog?.call('Skipped (source missing): ${proposal.oldName}');
      }
    }
    return renamed;
  }

  static Map<String, dynamic> _executeTool(
    LLMToolCall call,
    List<Map<String, String>> filesData,
    Map<String, RenameProposal> proposals,
    void Function(String message)? onLog,
  ) {
    switch (call.name) {
      case 'list_files':
        onLog?.call('Tool call: list_files (${filesData.length} files)');
        return {
          'files': [
            for (int i = 0; i < filesData.length; i++)
              {
                'id': i + 1,
                'name': filesData[i]['original_name'],
                'category': filesData[i]['category'],
              }
          ],
        };

      case 'rename_file':
        // Accept both a JSON number and a numeric string — smaller models
        // often quote integer arguments.
        final rawId = call.arguments['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        final newName = call.arguments['new_name']?.toString() ?? '';

        final path = (id != null && id >= 1 && id <= filesData.length)
            ? filesData[id - 1]['path']
            : null;
        if (path == null) {
          onLog?.call('Tool call rejected: unknown file id "$rawId"');
          return {
            'status': 'error',
            'message': 'Unknown id. Use an id exactly as returned by list_files '
                '(1..${filesData.length}).',
          };
        }
        if (!_isSafeFileName(newName)) {
          onLog?.call('Tool call rejected: unsafe name "$newName"');
          return {
            'status': 'error',
            'message': 'Invalid new_name: it must be a plain file name without '
                'directory separators, ".." sequences, or control characters.',
          };
        }
        final duplicate = proposals.entries
            .any((e) => e.key != path && e.value.newName.toLowerCase() == newName.toLowerCase());
        if (duplicate) {
          onLog?.call('Tool call rejected: duplicate target "$newName"');
          return {
            'status': 'error',
            'message': 'Another file is already being renamed to "$newName". Choose a unique name.',
          };
        }

        proposals[path] = RenameProposal(
          path: path,
          oldName: p.basename(path),
          newName: newName,
        );
        onLog?.call('Staged rename: ${p.basename(path)} -> $newName');
        return {'status': 'ok', 'staged': newName};

      default:
        return {
          'status': 'error',
          'message': 'Unknown tool "${call.name}". Available tools: list_files, rename_file.',
        };
    }
  }

  static String _buildSystemPrompt(String? template) {
    final base = (template == null || template.trim().isEmpty)
        ? 'You are a professional file renaming assistant.'
        : template.trim();
    return '$base\n\n'
        'You have access to tools. First call list_files to read the files, '
        'then call rename_file once for each file to stage its new name, '
        'using the numeric id from list_files to identify the file. '
        'You may batch multiple rename_file calls in one turn. '
        'If a call returns an error, correct the problem and retry. '
        'When every file has been staged, reply with a short plain-text summary '
        'and stop calling tools.';
  }

  static bool _isSafeFileName(String name) {
    return !name.contains('..') &&
        !name.contains('/') &&
        !name.contains('\\') &&
        !name.contains('\x00') &&
        name.trim().isNotEmpty;
  }
}
