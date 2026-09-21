part of 'task_queue_service.dart';

/// Overall bound on a video job: every poll, and the download after it.
const Duration _videoJobDeadline = Duration(minutes: 30);

/// The least time a finished job's download gets, even at the very end of
/// [_videoJobDeadline] — the job is already billed in full.
const Duration _videoDownloadFloor = Duration(minutes: 2);

/// Poll pacing for video jobs: first poll at once, then a mild backoff from
/// 7 s to a 20 s ceiling (it was a flat, uninterruptible 10 s).
Duration _videoPollInterval(int pollsSoFar) =>
    Duration(seconds: math.min(5 + pollsSoFar * 2, 20));

Map<String, dynamic> _compressReferenceInIsolate(Map<String, dynamic> input) {
  final result = ImageCompressor.compress(
    input['bytes'] as Uint8List,
    input['mimeType'] as String,
  );
  return {'bytes': result.bytes, 'mimeType': result.mimeType};
}

/// Why an image task that ran to the end still failed, or null when at least
/// one image was saved.
///
/// Zero results is a failure, not an empty success: a chat-surface image
/// model that answers in prose (a refusal, "I can't draw that", a question
/// back) returns HTTP 200 with no image, and the queue used to mark that task
/// completed with nothing in the gallery. The model's own words are the only
/// explanation the user gets, so they travel in the message.
@visibleForTesting
String? imageTaskFailure({
  required int received,
  required int unrecognised,
  required String reply,
}) {
  if (received > 0 && unrecognised < received) return null;
  final trimmed = reply.trim();
  final said = trimmed.isEmpty
      ? ''
      : ' Model said: ${trimmed.length > 500 ? '${trimmed.substring(0, 500)}…' : trimmed}';
  if (received == 0) return 'The model returned no image.$said';
  return 'None of the $received returned result(s) is a '
      'recognisable image; nothing was saved.$said';
}

/// Per-task-type execution logic for [TaskQueueService].
///
/// Implemented as a `part of` extension so it can use the service's private
/// members (`_emit`, `_queue`, callbacks) while keeping the queue-management
/// core file focused on scheduling and lifecycle.
extension TaskExecutors on TaskQueueService {
  Future<bool> _shouldUseStream(TaskItem task) async {
    if (!task.useStream) return false;
    if (task.modelDbId == null) return true; // Fallback for legacy

    final db = _db;
    final models = await db.getModels();
    final model = models.cast<LLMModel?>().firstWhere(
      (m) => m?.id == task.modelDbId,
      orElse: () => null,
    );

    if (model != null) {
      if (!model.supportsStream) {
        task.addLog(
          'Model does not support streaming. Falling back to standard request.',
        );
        return false;
      }
    }
    return true;
  }

  /// Builds a reference-image attachment, optionally pre-compressing it when
  /// the user opted in via the workbench "compress reference images" toggle
  /// (`task.parameters['compressReferenceImages']`). [referenceType] is
  /// preserved either way so Veo instance placement (first/last frame vs
  /// asset) keeps working on the compressed bytes.
  Future<LLMAttachment> _buildReferenceAttachment(
    TaskItem task,
    String path, {
    LLMReferenceType referenceType = LLMReferenceType.media,
  }) async {
    final mimeType = _getMimeType(path);
    if (task.parameters['compressReferenceImages'] != true) {
      return LLMAttachment.fromFile(
        File(path),
        mimeType,
        referenceType: referenceType,
      );
    }
    final raw = await File(path).readAsBytes();
    if (raw.length <= ImageCompressor.maxBytes) {
      return LLMAttachment.fromFile(
        File(path),
        mimeType,
        referenceType: referenceType,
      );
    }
    final compressed = await compute(_compressReferenceInIsolate, {
      'bytes': raw,
      'mimeType': mimeType,
    });
    return LLMAttachment.fromBytes(
      compressed['bytes'] as Uint8List,
      compressed['mimeType'] as String,
      referenceType: referenceType,
    );
  }

  Future<void> _executeImageProcessTask(TaskItem task) async {
    task.addLog(
      'Start processing with model: ${task.modelDbId ?? task.modelId}',
    );

    final outputDir = await _getEffectiveOutputDir(task);

    final attachments = await Future.wait(
      task.imagePaths.map((path) => _buildReferenceAttachment(task, path)),
    );

    final messages = [
      LLMMessage(
        role: LLMRole.user,
        content: task.parameters['prompt'] ?? '',
        attachments: attachments,
      ),
    ];

    final actualUseStream = await _shouldUseStream(task);

    // A fresh map, not a mutation of task.parameters: the probe is a function
    // value and task.parameters is persisted as JSON. Only the async image
    // task loop reads it — a cancelled task stops polling within ~1 s instead
    // of riding the job out.
    final requestOptions = <String, dynamic>{
      ...task.parameters,
      llmCancellationProbeKey: () => task.status == TaskStatus.cancelled,
    };

    var received = 0;
    var unrecognised = 0;
    final reply = StringBuffer();
    final prefix = FileUtils.safeFilenamePrefix(
      '${task.parameters['imagePrefix'] ?? 'result'}',
      fallback: 'result',
    );
    // One decomposition per request: every layer this run saves shares it.
    final layerSetId = '${task.id}_${DateTime.now().millisecondsSinceEpoch}';
    Future<void> save(Uint8List bytes, [GeneratedImageLayer? layer]) async {
      final i = received++;
      // Refused rather than defaulted to `.png`: bytes no image format
      // recognises are an HTML error page or a truncated body, and writing
      // them out put an unopenable file in the gallery under a success.
      if (imageMimeFromBytes(bytes) == null) {
        unrecognised++;
        task.addLog(
          'Warning: result ${i + 1} is not a recognisable image '
          '(${bytes.length} bytes) and was not saved.',
        );
        return;
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Named by what the bytes are, not by what any header claimed. Relays
      // have returned JPEG under `mimeType: image/png`, and `b64_json`
      // carries no type at all — every result used to be written as `.png`
      // regardless.
      final fileName =
          '${prefix}_${timestamp}_$i${imageExtensionFromBytes(bytes)}';
      final filePath = p.join(outputDir, fileName);

      final file = File(filePath);
      await file.writeAsBytes(bytes);
      task.resultPaths.add(filePath);
      if (layer != null) await _recordLayer(task, filePath, layerSetId, layer);
      _emit(task.id, TaskEventType.imageResult, filePath);
      task.addLog('Saved result image to: $filePath');

      onTaskCompleted?.call(file);
    }

    if (actualUseStream) {
      final stream = LLMService().requestStream(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        contextId: task.id,
        options: requestOptions,
      );

      await for (final chunk in stream) {
        if (task.status == TaskStatus.cancelled) break;

        if (chunk.textPart != null) {
          reply.write(chunk.textPart);
          _emit(task.id, TaskEventType.textChunk, chunk.textPart);
          task.addLog('AI: ${chunk.textPart}');
          refreshQueue();
        }

        // Saved the moment it arrives, not when the stream ends: on a route
        // that streams images one by one (Seedream on Ark) the first of a
        // group lands minutes before the last, and one that fails late no
        // longer takes the finished — and billed — ones with it.
        if (chunk.imagePart != null) {
          task.addLog('Received image chunk.');
          await save(chunk.imagePart!, chunk.imageLayer);
          refreshQueue();
        }
      }
    } else {
      final response = await LLMService().request(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        options: requestOptions,
        useStream: false,
      );

      if (response.text.isNotEmpty) {
        reply.write(response.text);
        _emit(task.id, TaskEventType.textChunk, response.text);
        task.addLog('AI: ${response.text}');
      }

      if (task.status != TaskStatus.cancelled) {
        for (final (i, bytes) in response.generatedImages.indexed) {
          await save(bytes,
              i < response.imageLayers.length ? response.imageLayers[i] : null);
        }
      }
    }

    task.addLog('LLM Task finished.');

    if (task.status == TaskStatus.cancelled) return;

    final failure = imageTaskFailure(
      received: received,
      unrecognised: unrecognised,
      reply: reply.toString(),
    );
    if (failure != null) throw Exception(failure);
  }

  /// Records where a saved decomposition file belongs, so the layer canvas
  /// can stack it back. Before the result event, so a gallery refreshed by
  /// that event already sees the row. A failure costs the placement, never
  /// the image: it is logged and the task carries on.
  Future<void> _recordLayer(TaskItem task, String path, String setId,
      GeneratedImageLayer layer) async {
    try {
      await ImageLayerRepository(db: _db).save(ImageLayer(
        path: path,
        setId: setId,
        zIndex: layer.zIndex,
        name: layer.name,
        description: layer.description,
        box: layer.box,
      ));
      task.addLog(layer.zIndex == 0
          ? 'Layer decomposition: saved the base.'
          : 'Layer decomposition: saved layer ${layer.zIndex}'
              '${layer.name == null ? '' : ' (${layer.name})'} at ${layer.box}.');
    } catch (e) {
      task.addLog('Warning: could not record layer ${layer.zIndex} of '
          '$path — the image is saved, its placement is not ($e).');
    }
  }

  /// Prompt refinement.
  ///
  /// Two modes:
  ///  * `parameters['sessionId']` present — one turn of the interactive
  ///    [PromptOptimizerAgent]; the conversation lives in the in-memory
  ///    session, images are attached on demand via tool calls.
  ///  * Otherwise — legacy one-shot refinement (kept for tasks restored from
  ///    the database).
  Future<void> _executePromptRefineTask(TaskItem task) async {
    final sessionId = task.parameters['sessionId'] as String?;
    if (sessionId != null) {
      final session = PromptOptimizerAgent.sessions[sessionId];
      if (session == null) {
        throw Exception(
          'Optimizer session is no longer available '
          '(it does not survive an app restart). Start a new conversation.',
        );
      }

      task.addLog(
        'Start assistant agent turn (${task.imagePaths.length} reference images, mode: ${session.mode.name}).',
      );

      // Per-model agent settings, resolved in one lookup: force viewing every
      // reference image, and the context window that budgets the turn.
      bool forceViewAll = false;
      bool acceptsImageInput = true;
      int? contextWindow;
      if (task.modelDbId != null) {
        final models = await _db.getModels();
        final model = models.cast<LLMModel?>().firstWhere(
          (m) => m?.id == task.modelDbId,
          orElse: () => null,
        );
        forceViewAll = model?.forceViewAllImages ?? false;
        contextWindow = model?.contextWindow;
        if (model != null) {
          // Layer-3 read: text-only models must not be offered image tools.
          acceptsImageInput = ModelDescriptor.of(
            model.modelId,
          ).acceptsImageInput;
        }
      }

      final contextRatio =
          double.tryParse(
            await _db.getSetting(
                  PromptOptimizerAgent.contextRatioSettingKey,
                ) ??
                '',
          ) ??
          PromptOptimizerAgent.defaultContextRatio;

      // Knowledge sub-agent opt-in (Settings, default off). Read here and
      // passed down so the agent stays free of app-state coupling.
      var kbSubAgentEnabled =
          (await _db.getSetting(
                PromptOptimizerAgent.kbSubAgentSettingKey,
              ) ??
              'false') ==
          'true';

      // Dedicated sub-agent model binding: absent = follow the session's
      // model. "Enabled" is not "available" (the playbook's double-loss
      // trap): a binding pointing at a deleted model disables delegation for
      // this turn — with a log naming the fix — rather than silently running
      // the sub-agent on a model the user deliberately routed away from.
      dynamic kbSubAgentModel;
      int? kbSubAgentWindow;
      // Whether the *effective* sub-agent model can see images decides the
      // draft kind's availability — following the session means inheriting
      // the session model's answer.
      var kbSubAgentAcceptsImages = acceptsImageInput;
      if (kbSubAgentEnabled) {
        final boundRaw = await _db.getSetting(
          PromptOptimizerAgent.kbSubAgentModelSettingKey,
        );
        final boundId = int.tryParse(boundRaw ?? '');
        if (boundId != null) {
          final all = await _db.getModels();
          final bound = all.cast<LLMModel?>().firstWhere(
            (m) => m?.id == boundId,
            orElse: () => null,
          );
          if (bound == null) {
            kbSubAgentEnabled = false;
            task.addLog(
              'Knowledge sub-agent model binding no longer exists — '
              'delegation disabled for this turn. Re-pick the model in '
              'Settings.',
            );
          } else {
            kbSubAgentModel = bound.id;
            kbSubAgentWindow = bound.contextWindow;
            kbSubAgentAcceptsImages = ModelDescriptor.of(
              bound.modelId,
            ).acceptsImageInput;
          }
        }
      }

      // Knowledge mode: resolve and validate the knowledge base, and pre-read
      // its entry file (the file map) for injection into the system prompt.
      String? knowledgeRoot;
      String? knowledgeEntry;
      if (session.usesKnowledgeBase) {
        final kb = KnowledgeBaseService();
        knowledgeRoot = await kb.getRoot();
        final status = await kb.validate(knowledgeRoot);
        if (status != KbStatus.ok) {
          throw Exception(
            'Knowledge base unavailable ($status). '
            'Configure its folder in Settings before using knowledge mode.',
          );
        }
        knowledgeEntry = kb.readEntry(knowledgeRoot!);
        task.addLog('Knowledge base: $knowledgeRoot');
      }

      await PromptOptimizerAgent.runTurn(
        session: session,
        modelIdentifier: task.modelDbId ?? task.modelId,
        systemPrompt: task.parameters['systemPrompt'],
        outputKind: PresetOutputKind.parse(task.parameters['outputKind']),
        forceViewAllImages: forceViewAll,
        acceptsImageInput: acceptsImageInput,
        knowledgeRoot: knowledgeRoot,
        knowledgeEntryContent: knowledgeEntry,
        referenceImages: task.imagePaths
            .map((path) => {'path': path, 'name': p.basename(path)})
            .toList(),
        contextId: task.id,
        contextWindow: contextWindow,
        contextRatio: contextRatio,
        kbSubAgentEnabled: kbSubAgentEnabled,
        kbSubAgentModelIdentifier: kbSubAgentModel,
        kbSubAgentContextWindow: kbSubAgentWindow,
        kbSubAgentAcceptsImages: kbSubAgentAcceptsImages,
        onLog: (msg) {
          task.addLog(msg);
          refreshQueue();
        },
        isCancelled: () => task.status == TaskStatus.cancelled,
      );

      if (session.refinedPrompt != null) {
        task.parameters['refinedPrompt'] = session.refinedPrompt;
      }
      task.addLog('Optimizer agent turn finished.');
      return;
    }

    task.addLog('Start prompt refinement.');

    final messages = <LLMMessage>[];
    if (task.parameters['systemPrompt'] != null) {
      messages.add(
        LLMMessage(
          role: LLMRole.system,
          content: task.parameters['systemPrompt'],
        ),
      );
    }

    final attachments = task.imagePaths
        .map((path) => LLMAttachment.fromFile(File(path), _getMimeType(path)))
        .toList();

    messages.add(
      LLMMessage(
        role: LLMRole.user,
        content: task.parameters['roughPrompt'] ?? '',
        attachments: attachments,
      ),
    );

    String resultText = '';
    final actualUseStream = await _shouldUseStream(task);
    final requestOptions = <String, dynamic>{
      ...task.parameters,
      llmCancellationProbeKey: () => task.status == TaskStatus.cancelled,
    };

    if (actualUseStream) {
      final stream = LLMService().requestStream(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        contextId: task.id,
        options: requestOptions,
      );

      await for (final chunk in stream) {
        if (task.status == TaskStatus.cancelled) break;
        if (chunk.textPart != null) {
          resultText += chunk.textPart!;
          _emit(task.id, TaskEventType.textChunk, chunk.textPart);
          refreshQueue();
        }
      }
    } else {
      final response = await LLMService().request(
        modelIdentifier: task.modelDbId ?? task.modelId,
        messages: messages,
        options: requestOptions,
        useStream: false,
        isCancelled: () => task.status == TaskStatus.cancelled,
      );
      resultText = response.text;
      _emit(task.id, TaskEventType.textChunk, resultText);
    }

    if (task.status == TaskStatus.cancelled) return;

    task.parameters['refinedPrompt'] = resultText;
    task.addLog('Refinement complete.');
  }

  /// AI batch rename via a standard LLM tool-use agent loop.
  ///
  /// Two modes:
  ///  * `parameters['proposals']` present — the user already confirmed these
  ///    renames in the preview dialog; apply them directly without another
  ///    LLM round-trip.
  ///  * Otherwise — run [AiRenameAgent] (list_files / rename_file tools) to
  ///    collect proposals, then apply them.
  Future<void> _executeAiRenameTask(TaskItem task) async {
    task.addLog('Start AI Batch Rename for ${task.imagePaths.length} files.');

    List<RenameProposal> proposals;

    final preConfirmed = task.parameters['proposals'];
    if (preConfirmed is List && preConfirmed.isNotEmpty) {
      proposals = preConfirmed
          .whereType<Map>()
          .map(
            (m) => RenameProposal(
              path: m['path']?.toString() ?? '',
              oldName: m['old_name']?.toString() ?? '',
              newName: m['new_name']?.toString() ?? '',
              // Only ever true because a person answered a conflict in the
              // review dialog; absent means the safe reading.
              overwrite: m['overwrite'] == true || m['overwrite'] == 'true',
            ),
          )
          .where((prop) => prop.path.isNotEmpty && prop.newName.isNotEmpty)
          .toList();
      task.addLog('Applying ${proposals.length} user-confirmed rename(s).');
    } else {
      final filesData = (task.parameters['filesData'] as List<dynamic>? ?? [])
          .map((e) => Map<String, String>.from(e as Map))
          .toList();

      proposals = await AiRenameAgent.collectProposals(
        modelIdentifier: task.modelDbId ?? task.modelId,
        filesData: filesData,
        systemPrompt: task.parameters['system_prompt'],
        instructions: task.parameters['instructions'],
        contextId: task.id,
        onLog: (msg) {
          task.addLog(msg);
          _emit(task.id, TaskEventType.textChunk, msg);
          refreshQueue();
        },
        isCancelled: () => task.status == TaskStatus.cancelled,
      );
      task.addLog('Agent staged ${proposals.length} rename proposal(s).');
    }

    if (task.status == TaskStatus.cancelled) return;

    final renamed = await AiRenameAgent.applyProposals(
      proposals,
      onLog: task.addLog,
    );

    task.addLog('AI Rename complete. $renamed file(s) renamed.');
  }

  Future<void> _executeVideoGenerateTask(TaskItem task) async {
    task.addLog(
      'Start video generation with model: ${task.modelDbId ?? task.modelId}',
    );

    final outputDir = await _getEffectiveOutputDir(task);

    // A job id persisted by an earlier run means the job was already accepted
    // — and billed. Resuming its poll is the only correct move; submitting
    // again would pay for the same video twice.
    final persistedOperation = task.operationName;
    final String operationName;
    if (persistedOperation != null && persistedOperation.isNotEmpty) {
      operationName = persistedOperation;
      task.addLog(
        'Resuming upstream job $operationName submitted by an earlier run; '
        'no new job is submitted.',
      );
    } else {
      operationName = await _submitVideoJob(task);
    }
    _emit(task.id, TaskEventType.progress, 0.05);

    // Polling through the shared loop (standard 14 §3): a failed poll is
    // ridden out up to three times in a row — a single one used to kill a
    // paid job — the sleep between polls is sliced so cancel lands within
    // half a second, and the interval backs off gently. Giving up is
    // LLMJobAbandoned, which names the job id.
    final jobStart = DateTime.now();
    final Map<String, dynamic> done;
    try {
      done = await pollJobUntilDone<Map<String, dynamic>>(
        job: 'Video job $operationName',
        jobId: operationName,
        deadline: _videoJobDeadline,
        interval: _videoPollInterval,
        sleepBeforeFirstPoll: false,
        isCancelled: () => task.status == TaskStatus.cancelled,
        // A terminal job state is thrown by the poll with no status code and
        // is not retryable; only transport failures and 5xx/429 polls count
        // toward the tolerance.
        isTransient: LLMService.isRetryable,
        logger: (msg, {level = 'INFO'}) {
          task.addLog(level == 'INFO' ? msg : '$level: $msg');
          refreshQueue();
        },
        fetch: () => LLMService().checkOperation(
          modelIdentifier: task.modelDbId ?? task.modelId,
          operationName: operationName,
          operationSurface: task.operationSurface,
          contextId: task.id,
          isCancelled: () => task.status == TaskStatus.cancelled,
        ),
        interpret: (opStatus) {
          if (opStatus['done'] == true) return opStatus;
          task.addLog('Generation in progress...');
          _emit(task.id, TaskEventType.progress, 0.5); // Placeholder progress
          return null;
        },
      );
    } on LLMCancelled {
      // The local task is over either way; this only decides whether the
      // upstream one goes with it. Most surfaces have no cancel and answer
      // null without a request — see LLMDispatcher.cancelOperation.
      final action = await LLMService().cancelOperation(
        modelIdentifier: task.modelDbId ?? task.modelId,
        operationName: operationName,
        operationSurface: task.operationSurface,
        contextId: task.id,
      );
      task.addLog(
        action == null
            ? 'Cancelled locally; the upstream job was left running.'
            : 'Cancelled locally; upstream reports "$action".',
      );
      // Cancelled upstream too: there is no job left to resume.
      if (action != null) await _forgetVideoJob(task);
      return;
    } on LLMApiException catch (e) {
      if (e.isJobEnded) await _forgetVideoJob(task);
      rethrow;
    }

    final rendered = done[videoRenderedSecondsKey];
    if (rendered is num) {
      await LLMService().settleVideoUsage(
        modelIdentifier: task.modelDbId ?? task.modelId,
        operationName: operationName,
        renderedSeconds: rendered,
        options: task.parameters,
        contextId: task.id,
      );
    }

    final response = done['response'] as Map?;
    final generated = response?['generateVideoResponse'] as Map?;
    final samples = generated?['generatedSamples'] as List?;
    final Map? video = samples != null && samples.isNotEmpty
        ? ((samples.first as Map?)?['video'] as Map?)
        : null;
    final videoUri = video?['uri'] as String?;
    if (videoUri == null || videoUri.isEmpty) {
      await _forgetVideoJob(task);
      throw Exception(
        'Operation $operationName finished but no video URI found. '
        'Response: ${jsonEncode(response)}',
      );
    }
    // The protocol that produced the URL decided whether it may carry the
    // channel's key (signed storage links must not).
    final requiresAuth = video?[videoRequiresAuthKey] == true;

    if (task.status == TaskStatus.cancelled) return;

    // Download, bounded by what is left of the job deadline — with a floor,
    // because a job that finished at minute 29 was billed in full and is
    // still worth fetching.
    task.addLog('Downloading video from: $videoUri');
    _emit(task.id, TaskEventType.progress, 0.8);

    var budget = _videoJobDeadline - DateTime.now().difference(jobStart);
    if (budget < _videoDownloadFloor) budget = _videoDownloadFloor;
    final headers = requiresAuth
        ? await _videoDownloadHeaders(task)
        : const <String, String>{};
    final downloadPath = await _downloadVideo(
      videoUri,
      task,
      outputDir,
      headers: headers,
      budget: budget,
    );

    task.resultPaths.add(downloadPath);
    _emit(
      task.id,
      TaskEventType.imageResult,
      downloadPath,
    ); // Reusing imageResult for video path
    task.addLog('Saved video to: $downloadPath');

    onTaskCompleted?.call(File(downloadPath));
  }

  /// Drops [task]'s upstream job id once the job is known to be over with
  /// nothing to fetch — failed, cancelled, expired, filtered, or finished
  /// without a video — so the task stops offering to resume it
  /// ([TaskQueueService.canResumeVideoJob]); a retry submits a new one. The
  /// id stays in the task log.
  Future<void> _forgetVideoJob(TaskItem task) async {
    if (task.operationName == null) return;
    task.addLog('Upstream job ${task.operationName} is over and cannot be '
        'resumed.');
    task.operationName = null;
    task.operationSurface = null;
    await _db.saveTask(task.toMap());
  }

  /// Builds the request, submits the job, and persists its id and surface
  /// before anything else can fail. Returns the operation id.
  Future<String> _submitVideoJob(TaskItem task) async {
    // 1. Prepare messages and attachments
    final attachments = <LLMAttachment>[];

    // First frame
    final firstFramePath = task.parameters['firstFramePath'] as String?;
    if (firstFramePath != null && firstFramePath.isNotEmpty) {
      attachments.add(
        await _buildReferenceAttachment(
          task,
          firstFramePath,
          referenceType: LLMReferenceType.firstFrame,
        ),
      );
      task.addLog('Added first frame: ${p.basename(firstFramePath)}');
    }

    // Last frame
    final lastFramePath = task.parameters['lastFramePath'] as String?;
    if (lastFramePath != null && lastFramePath.isNotEmpty) {
      attachments.add(
        await _buildReferenceAttachment(
          task,
          lastFramePath,
          referenceType: LLMReferenceType.lastFrame,
        ),
      );
      task.addLog('Added last frame: ${p.basename(lastFramePath)}');
    }

    // Reference images
    final referenceImagePaths =
        task.parameters['referenceImagePaths'] as List<dynamic>?;
    if (referenceImagePaths != null) {
      for (var path in referenceImagePaths) {
        final pathStr = path as String;
        attachments.add(
          await _buildReferenceAttachment(
            task,
            pathStr,
            referenceType: LLMReferenceType.asset,
          ),
        );
        task.addLog('Added reference image: ${p.basename(pathStr)}');
      }
    }

    final messages = [
      LLMMessage(
        role: LLMRole.user,
        content: task.parameters['prompt'] ?? '',
        attachments: attachments,
      ),
    ];

    // 2. Start Long Running Operation
    final ticket = await LLMService().startLongRunning(
      modelIdentifier: task.modelDbId ?? task.modelId,
      messages: messages,
      contextId: task.id,
      // A function cannot be persisted in task.parameters, so attach the
      // live cancellation probe only to this request copy. LLMService turns
      // it into an AbortableRequest trigger while the job is being submitted.
      options: {
        ...task.parameters,
        llmCancellationProbeKey: () => task.status == TaskStatus.cancelled,
      },
    );

    // Persist both halves of the job's provenance immediately. The id is
    // what a restart resumes and what a failure message names; the surface
    // keeps every later poll on the surface that issued the id, even if the
    // channel is re-pointed at another vendor while the job runs.
    task.operationName = ticket.name;
    task.operationSurface = ticket.surfaceId;
    await _db.saveTask(task.toMap());

    task.addLog('LRO started: ${ticket.name}');
    return ticket.name;
  }

  /// The channel's credential headers for a download whose URL needs them.
  /// A lookup failure downgrades to no headers — the job is done and billed,
  /// and a public link may well work without them.
  Future<Map<String, String>> _videoDownloadHeaders(TaskItem task) async {
    try {
      return await LLMService().downloadHeadersFor(
        modelIdentifier: task.modelDbId ?? task.modelId,
        contextId: task.id,
      );
    } catch (e) {
      task.addLog(
        'Warning: could not resolve channel credentials for the download '
        '($e); trying without them.',
      );
      return const {};
    }
  }

  /// Downloads a finished video: one retry, bounded by [budget], and only a
  /// real video container is kept (standard 14 §3.4).
  Future<String> _downloadVideo(
    String url,
    TaskItem task,
    String outputDir, {
    required Map<String, String> headers,
    required Duration budget,
  }) async {
    final deadline = DateTime.now().add(budget);
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      if (task.status == TaskStatus.cancelled) throw const LLMCancelled();
      if (!DateTime.now().isBefore(deadline)) break;
      try {
        return await _downloadVideoOnce(url, task, outputDir, headers, deadline);
      } on LLMCancelled {
        rethrow;
      } catch (e) {
        lastError = e;
        task.addLog('Video download attempt $attempt failed: $e');
        if (attempt == 1) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }
    throw Exception(
      'Video download failed after one retry: '
      '${lastError ?? 'the job deadline passed'}. The job itself finished '
      'upstream; its URL may still work for a while: $url',
    );
  }

  /// One download attempt, written to a `.part` file that becomes the result
  /// only after its leading bytes prove a video container. A non-200, an HTML
  /// error page served as 200, a stalled body or a cancel deletes the partial
  /// file instead of leaving an unplayable `.mp4` in the output folder.
  Future<String> _downloadVideoOnce(
    String url,
    TaskItem task,
    String outputDir,
    Map<String, String> headers,
    DateTime deadline,
  ) async {
    Duration left() {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('Video download ran past the job deadline.');
      }
      return remaining;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    File? part;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(left());
      headers.forEach(request.headers.add);
      final response = await request.close().timeout(left());
      if (response.statusCode != 200) {
        throw Exception('Failed to download video: HTTP ${response.statusCode}');
      }

      final prefix = FileUtils.safeFilenamePrefix(
        '${task.parameters['imagePrefix'] ?? 'video'}',
        fallback: 'video',
      );
      final stem = '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
      part = File(p.join(outputDir, '$stem.part'));
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          if (task.status == TaskStatus.cancelled) throw const LLMCancelled();
          left();
          sink.add(chunk);
          received += chunk.length;
        }
      } finally {
        await sink.close();
      }

      final raf = await part.open();
      final Uint8List head;
      try {
        head = await raf.read(videoMagicHeadLength);
      } finally {
        await raf.close();
      }
      final extension = videoExtensionFromBytes(head);
      if (extension == null) {
        throw Exception(
          'Downloaded body is not a video ($received bytes, content-type '
          '${response.headers.contentType ?? 'none'}) — most likely an error '
          'page or an expired link.',
        );
      }

      final saved = await part.rename(p.join(outputDir, '$stem$extension'));
      part = null;
      return saved.path;
    } catch (_) {
      final leftover = part;
      if (leftover != null) {
        try {
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {
          // Best effort: a partial file that cannot be removed is still
          // better reported than hidden behind a second error.
        }
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _executeDownloadTask(TaskItem task) async {
    task.addLog('Start downloading ${task.imagePaths.length} images.');

    final outputDir = await _getEffectiveOutputDir(task);

    // A download restored after a restart has no cookies of its own — task
    // rows never store them — so it asks the history for the page's host.
    // An empty value is kept in the row and means "queued without cookies".
    var cookies = task.parameters['cookies'] as String?;
    if (cookies == null) {
      final host = Uri.tryParse('${task.parameters['url'] ?? ''}')?.host ?? '';
      cookies = await CookieRepository(db: _db).lookup(host);
    }
    final formattedCookies = WebScraperService().parseCookies(cookies ?? '');
    final prefix = FileUtils.safeFilenamePrefix(
      '${task.parameters['prefix'] ?? 'download'}',
      fallback: 'download',
    );

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    for (int i = 0; i < task.imagePaths.length; i++) {
      if (task.status == TaskStatus.cancelled) break;

      final url = task.imagePaths[i];
      task.addLog('Downloading: $url');
      refreshQueue();

      try {
        final request = await client
            .getUrl(Uri.parse(url))
            .timeout(const Duration(seconds: 30));
        if (formattedCookies.isNotEmpty) {
          request.headers.add(HttpHeaders.cookieHeader, formattedCookies);
        }

        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 200) {
          throw Exception('Failed to download image: ${response.statusCode}');
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = _getExtensionFromUrl(url);
        final fileName = '${prefix}_${timestamp}_$i$extension';
        final filePath = p.join(outputDir, fileName);

        final file = File(filePath);
        final sink = file.openWrite();
        try {
          await response.timeout(const Duration(seconds: 60)).pipe(sink);
        } catch (e) {
          await sink.close();
          rethrow;
        }
        task.resultPaths.add(filePath);
        _emit(task.id, TaskEventType.imageResult, filePath);
        _emit(
          task.id,
          TaskEventType.progress,
          (i + 1) / task.imagePaths.length,
        );
        task.addLog('Saved to: $filePath');

        onTaskCompleted?.call(file);
        refreshQueue();
      } catch (e) {
        task.addLog('Failed to download $url: $e');
        // We continue with other images even if one fails
      }
    }
    client.close();
  }

  String _getExtensionFromUrl(String url) {
    final path = Uri.parse(url).path;
    final ext = p.extension(path).toLowerCase();
    if (ext.isEmpty ||
        !['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].contains(ext)) {
      return '.png'; // Default
    }
    return ext;
  }

  String _getMimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.png') return 'image/png';
    if (ext == '.webp') return 'image/webp';
    return 'image/jpeg';
  }

  /// Checks if primary output is writable, returns it or falls back to Result Cache.
  Future<String> _getEffectiveOutputDir(TaskItem task) async {
    final db = _db;
    final String? primary = await db.getSetting('output_directory');

    // Result Cache is always initialized in GalleryState for iOS/macOS
    String? fallback;
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final appCache = (await db.getSetting('result_cache_directory')) ?? '';
        if (appCache.isNotEmpty) fallback = appCache;
      }
    } catch (_) {}

    if (primary == null || primary.isEmpty) {
      if (fallback != null) return fallback;
      throw Exception('Output directory not set!');
    }

    try {
      final dir = Directory(primary);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      // Test writability
      final testFile = File(p.join(primary, '.write_test'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return primary;
    } catch (e) {
      task.addLog(
        'Warning: Primary output directory is unwritable ($e). Falling back to Result Cache.',
      );
      if (fallback != null) return fallback;
      rethrow;
    }
  }
}
