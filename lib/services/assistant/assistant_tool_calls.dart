part of 'prompt_optimizer_agent.dart';

/// Digest cap for what a delegate run reports back into the main context —
/// enough to judge the findings, deliberately not enough to substitute for
/// reading the note (the playbook's 800-char rule: a digest that could
/// stand in for the note would just move the flooding one level up).
const int _delegateSummaryChars = 800;

/// Runs one `delegate` call: validates with zero side effects, then runs a
/// [SubAgentRunner] over the knowledge base and returns a digest result.
///
/// [modelIdentifier] and [contextWindow] describe the model the sub-agent
/// actually runs on — the session's own by default, or the dedicated
/// binding from Settings when one is configured (resolved by the task
/// executor; a broken binding disables delegation there rather than
/// silently falling back here).
Future<Map<String, dynamic>> _executeDelegate(
  LLMToolCall call,
  PromptOptimizerSession session,
  dynamic modelIdentifier,
  String? knowledgeRoot, {
  required Set<String> availableKinds,
  required List<Map<String, String>> referenceImages,
  int? contextWindow,
  String? contextId,
  void Function(String message)? onLog,
  bool Function()? isCancelled,
}) async {
  // Precondition checks first, with zero side effects: a refused delegate
  // must not have sent a request or produced a transcript entry. The model
  // can hallucinate a kind it was never offered; what decides is each
  // kind's precondition, not the schema it happened to see (same rule as
  // write_knowledge_file).
  final kind = call.arguments['kind']?.toString() ?? '';
  if (!availableKinds.contains(kind)) {
    return {
      'status': 'error',
      'message': 'Delegate kind "$kind" is not available here'
          '${availableKinds.isEmpty ? '' : ' (available: ${availableKinds.join(', ')})'}. '
          '"knowledge" needs a knowledge-base session; "draft" needs '
          'reference images and an image-capable sub-agent model.',
    };
  }
  final task = call.arguments['task']?.toString().trim() ?? '';
  if (task.isEmpty) {
    return {
      'status': 'error',
      'message': 'The task argument must not be empty. Write a '
          'self-contained brief — the sub-agent sees nothing of this '
          'conversation.',
    };
  }

  if (kind == 'draft') {
    return _runDraftDelegate(
      call,
      session,
      modelIdentifier,
      task,
      referenceImages,
      contextId: contextId,
      onLog: onLog,
      isCancelled: isCancelled,
    );
  }

  // kind == 'knowledge'
  if (knowledgeRoot == null) return _kbUnavailable();
  final rawPaths = call.arguments['paths'];
  final paths = [
    if (rawPaths is List)
      for (final p in rawPaths)
        if (p.toString().trim().isNotEmpty) p.toString().trim(),
  ];

  onLog?.call('Tool call: delegate (knowledge) — ${_clipPreview(task)}');
  session._addEntry(OptimizerChatEntry(
    kind: OptimizerEntryKind.tool,
    text: _clipPreview(task),
    toolName: 'delegate',
  ));

  final result = await SubAgentRunner.run(
    modelIdentifier: modelIdentifier,
    systemPrompt: _kbSubAgentSystemPrompt,
    task: PromptOptimizerAgent.buildDelegateTask(task, paths),
    tools: _knowledgeTools,
    executeTool: (c, occupied) =>
        _executeSubAgentKbTool(c, knowledgeRoot, contextWindow, occupied, onLog),
    isCancelled: isCancelled,
    onLog: (m) => onLog?.call('[KB sub-agent] $m'),
    contextId: contextId,
    usageTag: 'subagent:knowledge',
    // The same tally the main loop budgets with — tool-call arguments
    // included — so the sub-agent's read cap is not over-granted.
    measureOccupancy: (messages) => PromptOptimizerAgent.occupiedChars('', messages),
  );
  return _finishDelegateRun(session, task, result, onLog);
}

String _clipPreview(String task) =>
    task.length > 120 ? '${task.substring(0, 120)}…' : task;

/// One `draft` run: a single-shot sub-agent over exactly one reference
/// image. No tools and one turn — the whole point is that the image and
/// its description live in the sub-agent's context, not the main one.
Future<Map<String, dynamic>> _runDraftDelegate(
  LLMToolCall call,
  PromptOptimizerSession session,
  dynamic modelIdentifier,
  String task,
  List<Map<String, String>> referenceImages, {
  String? contextId,
  void Function(String message)? onLog,
  bool Function()? isCancelled,
}) async {
  final rawImageId = call.arguments['image_id'];
  final imageId =
      rawImageId is int ? rawImageId : int.tryParse(rawImageId?.toString() ?? '');
  if (imageId == null || imageId < 1 || imageId > referenceImages.length) {
    return {
      'status': 'error',
      'message': 'Pass image_id between 1 and ${referenceImages.length} — '
          'the ids list_reference_images shows. One image per draft run.',
    };
  }
  final ref = referenceImages[imageId - 1];
  final path = ref['path'];
  if (path == null || !File(path).existsSync()) {
    return {
      'status': 'error',
      'message': 'Reference image #$imageId is no longer available on disk.',
    };
  }

  onLog?.call('Tool call: delegate (draft, image #$imageId) — ${_clipPreview(task)}');
  session._addEntry(OptimizerChatEntry(
    kind: OptimizerEntryKind.tool,
    text: '[draft #$imageId] ${_clipPreview(task)}',
    toolName: 'delegate',
  ));

  final result = await SubAgentRunner.run(
    modelIdentifier: modelIdentifier,
    systemPrompt: _draftSubAgentSystemPrompt,
    task: task,
    attachments: [
      LLMAttachment.fromFile(
        File(path),
        _mimeTypeFor(path),
        // viewOnly: eligible for lossy recompression when oversized — the
        // sub-agent only describes it, nothing feeds back into generation.
        referenceType: LLMReferenceType.viewOnly,
      ),
    ],
    tools: const [],
    executeTool: (_, _) => const {
      'status': 'error',
      'message': 'A draft run has no tools — answer in plain text.',
    },
    maxTurns: 1,
    isCancelled: isCancelled,
    onLog: (m) => onLog?.call('[draft sub-agent] $m'),
    contextId: contextId,
    usageTag: 'subagent:draft',
  );
  return _finishDelegateRun(session, task, result, onLog);
}

/// Shared tail of every delegate run: cancellation, the empty-output rule
/// (no note, no digest — an empty note would just relocate the nothing),
/// then note storage + digest.
Future<Map<String, dynamic>> _finishDelegateRun(
  PromptOptimizerSession session,
  String task,
  SubAgentResult result,
  void Function(String message)? onLog,
) async {
  if (result.cancelled) {
    return {
      'status': 'cancelled',
      'message': 'The user cancelled the task while the sub-agent was '
          'running.',
    };
  }
  final output = result.output.trim();
  if (output.isEmpty) {
    return {
      'status': 'error',
      'message': 'The sub-agent returned nothing. Try a narrower or more '
          'specific task, or do the work yourself with your own tools.',
    };
  }
  onLog?.call('Sub-agent finished in ${result.turnsUsed} turn(s), '
      '${output.length} chars of findings.');

  // Full findings go to the session's note store; the main context gets a
  // digest and the note id. Best-effort: a storage failure downgrades to
  // digest-only rather than failing a research run that already succeeded.
  AssistantNote? note;
  try {
    note = await AssistantNoteRepository().insert(
      sessionId: session.id,
      title: task.length > 80 ? task.substring(0, 80) : task,
      content: output,
    );
  } catch (e) {
    onLog?.call('Note storage failed (returning digest only): $e');
  }

  final truncated = output.length > _delegateSummaryChars;
  return {
    'status': 'ok',
    if (note != null) 'note_id': note.id,
    'summary': truncated
        ? '${output.substring(0, _delegateSummaryChars)}…'
        : output,
    if (note != null && truncated)
      'hint': 'Full findings (${output.length} chars) are saved as note '
          '${note.id} — call read_note with that note_id when you need the '
          'detail.',
  };
}

/// Runs one `read_note` call: pages a stored sub-agent note back into the
/// conversation. Session-scoped (a foreign note id reads as not-found) and
/// behind the same read-cap gate as knowledge reads — its results are
/// elided by [_elide] later, exactly like a knowledge read, and can simply
/// be re-read then (notes have no staleness: nothing rewrites them).
Future<Map<String, dynamic>> _executeReadNote(
  LLMToolCall call,
  PromptOptimizerSession session, {
  required String systemPrompt,
  required int? contextWindow,
  void Function(String message)? onLog,
}) async {
  final rawId = call.arguments['note_id'];
  final noteId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
  if (noteId == null) {
    return {
      'status': 'error',
      'message':
          'Pass note_id — the integer id a delegate result returned.',
    };
  }
  final rawPage = call.arguments['page'];
  final page =
      rawPage is int ? rawPage : int.tryParse(rawPage?.toString() ?? '') ?? 1;
  onLog?.call('Tool call: read_note #$noteId (page $page)');

  final cap = _readCapNow(session, systemPrompt, contextWindow);
  if (cap < _minReadChars) {
    return {
      'status': 'error',
      'message': 'Not enough context left to read the note — work with the '
          'summary you already have.',
    };
  }

  final note =
      await AssistantNoteRepository().get(noteId, sessionId: session.id);
  if (note == null) {
    return {
      'status': 'error',
      'message': 'No note $noteId in this conversation. Use the note_id a '
          'delegate result returned.',
    };
  }
  session._addEntry(OptimizerChatEntry(
    kind: OptimizerEntryKind.tool,
    text: '#$noteId ${note.title}',
    toolName: 'read_note',
  ));

  // Paged like knowledge reads: a fixed page size keeps page numbers
  // stable across reads; only a window tighter than one page shrinks it.
  final pageSize = cap < KnowledgeBaseService.pageSize
      ? cap
      : KnowledgeBaseService.pageSize;
  final content = note.content;
  final bounds = KnowledgeBaseService.pageBoundaries(content, pageSize);
  final total = bounds.length;
  final idx = page < 1 ? 1 : (page > total ? total : page);
  final start = bounds[idx - 1];
  final end = idx < total ? bounds[idx] : content.length;
  return {
    'note_id': noteId,
    'page': idx,
    'total_pages': total,
    'content': content.substring(start, end),
    if (total > idx)
      'note': 'Note continues — request the next page only if this part '
          'is not enough.',
  };
}

/// The sub-agent's view of the knowledge tools: same wire definitions
/// ([_knowledgeTools]), lean execution — no session, no transcript entries,
/// no live-read cache (its context is fresh). Reads are budgeted against
/// the **sub-agent's own** model window ([contextWindow], tri-state) and
/// its run's occupancy — the whole point of delegation is that this budget
/// is independent of how full the main conversation is.
Map<String, dynamic> _executeSubAgentKbTool(
  LLMToolCall call,
  String knowledgeRoot,
  int? contextWindow,
  int occupiedChars,
  void Function(String message)? onLog,
) {
  switch (call.name) {
    case 'list_knowledge_files':
      final dir = call.arguments['dir']?.toString();
      onLog?.call('[KB sub-agent] list_knowledge_files (${dir ?? '.'})');
      try {
        final files = KnowledgeBaseService().listFiles(knowledgeRoot, dir: dir);
        return {'files': [for (final f in files) f.toJson()]};
      } on KbPathException catch (e) {
        return {'status': 'error', 'message': e.message};
      } catch (e) {
        return {'status': 'error', 'message': 'Failed to list knowledge files: $e'};
      }
    case 'read_knowledge_file':
      final relPath = call.arguments['path']?.toString() ?? '';
      final rawPage = call.arguments['page'];
      final page =
          rawPage is int ? rawPage : int.tryParse(rawPage?.toString() ?? '') ?? 1;
      onLog?.call('[KB sub-agent] read_knowledge_file $relPath (page $page)');
      final cap = ContextBudget.readCapChars(contextWindow, occupiedChars);
      if (cap < _minReadChars) {
        return {
          'status': 'error',
          'message': 'Not enough context left in this research run to read '
              'more. Write your findings now from what you have already '
              'read.',
        };
      }
      try {
        final result = KnowledgeBaseService().readFile(knowledgeRoot, relPath,
            page: page, maxChars: cap);
        return {
          'path': relPath,
          'page': result.page,
          'total_pages': result.totalPages,
          'content': result.content,
          if (result.totalPages > result.page)
            'note': 'File continues — request the next page only if this '
                'part is not enough.',
        };
      } on KbPathException catch (e) {
        return {'status': 'error', 'message': e.message};
      } catch (e) {
        return {'status': 'error', 'message': 'Failed to read $relPath: $e'};
      }
    default:
      return {
        'status': 'error',
        'message': 'Unknown tool "${call.name}". Available tools: '
            'list_knowledge_files, read_knowledge_file.',
      };
  }
}

/// The `write_knowledge_file` tool.
///
/// Out here rather than in [_executeTool]'s switch because it can now
/// await: with per-edit confirmation off it writes the staged edit
/// straight through. Same placement as `delegate` and `read_note`, and
/// the same pairing contract — every path returns a result.
Future<Map<String, dynamic>> _executeWriteKnowledge(
  LLMToolCall call,
  PromptOptimizerSession session,
  String? knowledgeRoot,
  void Function(String message)? onLog,
) async {
  if (knowledgeRoot == null) return _kbUnavailable();
  // The tool is only registered when both halves of `canWriteKnowledge`
  // hold, but a model can hallucinate a tool name it was never offered —
  // the session, not the tool list, is what decides whether edits may be
  // proposed at all. The two halves are refused separately because they are
  // different situations: one is the wrong mode, the other is the user
  // having said no, and telling the model "wrong mode" when it is in the
  // right one invites it to keep trying.
  if (!session.writePolicy.allowWrites) {
    return {
      'status': 'error',
      'message': 'The user has turned off knowledge-base writing for this '
          'session. Do not retry — say what you would have changed instead.',
    };
  }
  if (!session.canWriteKnowledge) {
    return {
      'status': 'error',
      'message': 'This session is read-only. Knowledge files can only be '
          'edited in the knowledge-base maintenance mode.',
    };
  }
  final writePath = call.arguments['path']?.toString() ?? '';
  final writeContent = call.arguments['content']?.toString() ?? '';
  final mode = call.arguments['mode']?.toString() ?? 'replace_file';
  final section = call.arguments['section']?.toString().trim();
  onLog?.call('Tool call: write_knowledge_file $writePath '
      '(${writeContent.length} chars, $mode${section == null || section.isEmpty ? '' : ' "$section"'})');
  if (writePath.trim().isEmpty) {
    return {'status': 'error', 'message': 'The path argument must not be empty.'};
  }
  if (writeContent.isEmpty) {
    return {
      'status': 'error',
      'message': 'The content argument must not be empty. Pass the complete '
          '${mode == 'replace_file' ? 'file' : 'section'} content.',
    };
  }
  if (mode != 'replace_file' && mode != 'replace_section' && mode != 'append') {
    return {
      'status': 'error',
      'message': 'Unknown mode "$mode". Use replace_file, replace_section or append.',
    };
  }
  if (mode == 'replace_section' && (section == null || section.isEmpty)) {
    return {
      'status': 'error',
      'message': 'replace_section needs a section: the heading line exactly as '
          'the file spells it (for example "## Lighting").',
    };
  }
  try {
    final kb = KnowledgeBaseService();
    final existing = kb.readFullFile(knowledgeRoot, writePath);
    if (mode != 'replace_file' && existing == null) {
      return {
        'status': 'error',
        'message': '$writePath does not exist, so there is no section to '
            '$mode into. Create it with the whole-file mode.',
      };
    }
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
    // The targeted modes send one section over the wire; what is staged is
    // still the whole file, spliced here, so the diff card, the suspicious-
    // shrink check and the apply path see exactly what they always did.
    final String newContent;
    if (mode == 'replace_file') {
      newContent = writeContent;
    } else {
      try {
        newContent = KnowledgeBaseService.spliceSection(
          existing!,
          section == null || section.isEmpty ? null : section,
          writeContent,
          append: mode == 'append',
        );
      } on KbSectionNotFound catch (e) {
        return {'status': 'error', 'message': e.message};
      }
    }
    final editId = session._stageKbEdit(
      relPath: writePath,
      newContent: newContent,
      oldContent: existing,
      knowledgeRoot: knowledgeRoot,
      note: call.arguments['note']?.toString(),
    );
    // Staged either way, then applied here when the user has turned per-edit
    // confirmation off. Going through the same card rather than writing
    // behind its back is what keeps the transcript a truthful record: the
    // edit is still reviewable after the fact, still shows its diff, and
    // still says what happened to it.
    if (!session.writePolicy.confirmEachWrite) {
      // The tool result below (or the error the outer catch returns) already
      // tells the model what happened — no outcomes record for this one.
      session._reportedKbEditIds.add(editId);
      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: editId);
      return {
        'status': 'ok',
        'message': 'Wrote $writePath. Per-edit confirmation is off for this '
            'session, so the change is already on disk.',
      };
    }
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
}

Map<String, dynamic> _executeTool(
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
          // Named even though the content is not repeated, so the UI can
          // still credit the file as something this answer rests on. A
          // cache hit means the model is *using* it, not ignoring it, and a
          // citation list that dropped it would shrink as a conversation
          // went on. `_liveReadPages` is unaffected: it requires a non-null
          // `content` (see the invariant it documents), which this lacks.
          'path': relPath,
          'note': 'This page is already in the conversation — refer to the earlier result instead of re-reading it.',
        };
      }
      final cap = _readCapNow(session, systemPrompt, contextWindow,
          keepCurrentTurnImages: forceViewAllImages);
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
      // Result images (fed back from generation) are the same list entries
      // as references — the distinction is derived from the feedback
      // messages in history, so it needs no extra plumbing or persistence.
      final resultInfo = PromptOptimizerAgent.resultImageInfoByName(session.history);
      return {
        'images': [
          for (int i = 0; i < referenceImages.length; i++)
            () {
              final name = referenceImages[i]['name'];
              final info = resultInfo[name];
              return {
                'id': i + 1,
                'name': name,
                'size_kb': _fileSizeKb(referenceImages[i]['path']),
                'kind': info == null ? 'reference' : 'result',
                if (info?.promptVersion != null) 'prompt_version': info!.promptVersion,
                if (info != null && info.feedback.isNotEmpty)
                  'user_feedback': info.feedback.length > 300
                      ? '${info.feedback.substring(0, 300)}…'
                      : info.feedback,
              };
            }(),
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
      // Derived, not tracked: only refuse when the earlier attachment is
      // still inside the recent window and therefore actually part of the
      // next request. Once _trimForSend has elided it (or compaction folded
      // it), the model may legitimately ask to see the image again.
      if (_liveViewedPaths(session, keepCurrentTurnImages: forceViewAllImages)
              .contains(path) ||
          alreadyAttached) {
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

Map<String, dynamic> _kbUnavailable() => {
      'status': 'error',
      'message': 'The knowledge base is not available in this session.',
    };

int _fileSizeKb(String? path) {
  if (path == null) return 0;
  try {
    return (File(path).lengthSync() / 1024).round();
  } catch (_) {
    return 0;
  }
}

String _mimeTypeFor(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext == '.png') return 'image/png';
  if (ext == '.webp') return 'image/webp';
  if (ext == '.gif') return 'image/gif';
  return 'image/jpeg';
}
