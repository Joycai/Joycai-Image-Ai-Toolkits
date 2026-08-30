part of 'app_state.dart';

/// Workbench, video and per-family image-parameter configuration, plus task
/// submission. Split out of [AppState] as a `part of` extension; notifications
/// route through [AppState.notify] since `notifyListeners` is protected.
extension AppStateWorkbench on AppState {
  Future<void> setIsMarkdownWorkbench(bool value) async {
    isMarkdownWorkbench = value;
    await _db.saveSetting('is_markdown_workbench', value.toString());
    notify();
  }

  Future<void> setIsMarkdownRefinerSource(bool value) async {
    isMarkdownRefinerSource = value;
    await _db.saveSetting('is_markdown_refiner_source', value.toString());
    notify();
  }

  Future<void> setIsMarkdownRefinerTarget(bool value) async {
    isMarkdownRefinerTarget = value;
    await _db.saveSetting('is_markdown_refiner_target', value.toString());
    notify();
  }

  /// Moves the workbench's configuration and persists it.
  ///
  /// The fields move and [AppState.notify] fires **before** anything is
  /// written, which is the whole shape of this method. Awaiting each
  /// `saveSetting` first put a SQLite round trip between the user's click on a
  /// model and the panel showing it — on Windows the write is a real
  /// transaction on a file the virus scanner is watching, so the control
  /// visibly lagged the pointer. Nothing here reads back from the database, so
  /// the write has no business being on that path.
  ///
  /// Still returns the writes' future, so a caller that needs the value on
  /// disk — a test, or a shutdown path — can wait for it. No caller does
  /// today, which is why the failure path is logged here rather than left to
  /// them: an unobserved rejection is a silent divergence between what the
  /// panel is showing and what survives a restart.
  Future<void> updateWorkbenchConfig({
    String? modelId,
    String? prompt,
    bool? useStream,
    bool? compressReferenceImages,
  }) {
    final writes = <Future<void>>[];

    if (modelId != null) {
      lastSelectedModelId = modelId;
      writes.add(_db.saveSetting('last_model_id', modelId));
    }
    if (prompt != null) {
      lastPrompt = prompt;
      writes.add(_db.saveSetting('last_prompt', prompt));
    }
    if (useStream != null) {
      this.useStream = useStream;
      writes.add(_db.saveSetting('workbench_use_stream', useStream.toString()));
    }
    if (compressReferenceImages != null) {
      this.compressReferenceImages = compressReferenceImages;
      writes.add(_db.saveSetting(
          'workbench_compress_reference_images', compressReferenceImages.toString()));
    }

    notify();
    // Logged rather than left to the caller: [notify] has already run, so the
    // panel is showing a value the disk may not have. Without this the two
    // diverge in silence and the next launch quietly reverts the user's
    // choice. `Future.wait` keeps only the first failure of the set — it
    // attaches a handler to each write, so nothing escapes to the zone — which
    // is enough here, since one message naming the failure is the whole
    // remedy.
    return Future.wait(writes).then((_) {}).catchError((Object e) {
      addLog('Failed to persist workbench config: $e', level: 'ERROR');
    });
  }

  /// Records the workbench prompt as the user types.
  ///
  /// Deliberately silent, and deliberately not [updateWorkbenchConfig]: nothing
  /// in the app rebuilds off [AppState.lastPrompt] except the editor that owns
  /// the text, and that editor already has it in its own controller. Notifying
  /// per keystroke meant every character rebuilt the navigation rail, the
  /// gallery grid, the log console and the sidebar — this is what made typing
  /// drop frames. The one writer that *does* need the rebuild is
  /// `_handleOptimizerApply`, which drops a finished prompt in from the
  /// assistant tab; that keeps going through [updateWorkbenchConfig] so the
  /// editor picks it up.
  ///
  /// The field moves synchronously so it is never stale — only the SQLite write
  /// is deferred, and it is deferred on [AppState], which outlives the panel,
  /// so closing the workbench mid-sentence still persists the draft.
  void setPromptDraft(String prompt) {
    lastPrompt = prompt;
    _promptSaveTimer?.cancel();
    _promptSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _db.saveSetting('last_prompt', lastPrompt);
    });
  }

  /// The video panel's counterpart to [setPromptDraft]; same reasoning.
  void setVideoPromptDraft(String prompt) {
    lastVideoPrompt = prompt;
    _videoPromptSaveTimer?.cancel();
    _videoPromptSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _db.saveSetting('last_video_prompt', lastVideoPrompt);
    });
  }

  // --- Per-family image generation parameters ------------------------------

  Future<void> loadImageParams() async {
    final raw = await _db.getSetting('workbench_image_params');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _imageParamStore = decoded.map((k, v) => MapEntry(k, v.toString()));
        return;
      } catch (_) {/* fall through to legacy migration */}
    }
    // Migrate the old single-set params into the nanoBanana namespace.
    final legacyAr = await _db.getSetting('last_aspect_ratio');
    final legacyRes = await _db.getSetting('last_resolution');
    final ns = ModelFamily.geminiImage.name;
    if (legacyAr != null) _imageParamStore['$ns.aspectRatio'] = legacyAr;
    if (legacyRes != null) _imageParamStore['$ns.imageSize'] = legacyRes;
  }

  String _familyKey(String modelId) =>
      ModelFamilyClassifier.classify(modelId).name;

  /// Current value for [spec] under the selected [modelId], validated against
  /// the spec's options (falls back to the spec default).
  String getImageParam(String modelId, ParamSpec spec) {
    final stored = _imageParamStore['${_familyKey(modelId)}.${spec.key}'];
    return spec.normalize(stored);
  }

  Future<void> setImageParam(String modelId, String paramKey, String value) async {
    _imageParamStore = {
      ..._imageParamStore,
      '${_familyKey(modelId)}.$paramKey': value,
    };
    imageParamsRevision++;
    await _db.saveSetting('workbench_image_params', jsonEncode(_imageParamStore));
    notify();
  }

  /// Validated parameter map to send with a generation task for [modelId].
  Map<String, dynamic> effectiveImageParams(String modelId) {
    final caps = ModelCapabilities.forModel(modelId);
    final result = <String, dynamic>{};
    for (final spec in caps.imageParams) {
      result[spec.key] = getImageParam(modelId, spec);
    }
    return result;
  }

  // --- Per-family video generation parameters ------------------------------

  Future<void> loadVideoParams() async {
    final raw = await _db.getSetting('workbench_video_params');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _videoParamStore = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {/* ignore malformed */}
    }
  }

  String getVideoParam(String modelId, ParamSpec spec) {
    final stored = _videoParamStore['${_familyKey(modelId)}.${spec.key}'];
    return spec.normalize(stored);
  }

  Future<void> setVideoParam(String modelId, String paramKey, String value) async {
    _videoParamStore = {
      ..._videoParamStore,
      '${_familyKey(modelId)}.$paramKey': value,
    };
    videoParamsRevision++;
    await _db.saveSetting('workbench_video_params', jsonEncode(_videoParamStore));
    notify();
  }

  /// Validated parameter map of video-only extras (seconds, quality, …) for
  /// the model. Empty for families without [ModelCapabilities.videoParams]
  /// (e.g. Veo, which still uses its fixed enums).
  Map<String, dynamic> effectiveVideoParams(String modelId) {
    final caps = ModelCapabilities.forModel(modelId);
    final result = <String, dynamic>{};
    for (final spec in caps.videoParams) {
      result[spec.key] = getVideoParam(modelId, spec);
    }
    return result;
  }

  Future<void> updateVideoConfig({
    String? modelId,
    VeoResolution? resolution,
    VeoAspectRatio? aspectRatio,
    String? prompt,
  }) async {
    if (modelId != null) {
      lastVideoModelId = modelId;
      await _db.saveSetting('last_video_model_id', modelId);
    }
    if (resolution != null) {
      lastVideoResolution = resolution;
      await _db.saveSetting('last_video_resolution', resolution.value);
    }
    if (aspectRatio != null) {
      lastVideoAspectRatio = aspectRatio;
      await _db.saveSetting('last_video_aspect_ratio', aspectRatio.value);
    }
    if (prompt != null) {
      lastVideoPrompt = prompt;
      await _db.saveSetting('last_video_prompt', prompt);
    }
    notify();
  }

  Future<void> submitTask(dynamic modelIdentifier, Map<String, dynamic> params, {String? modelIdDisplay}) async {
    final prompt = params['prompt'] as String? ?? '';
    final isVideoTask = params['taskType'] == TaskType.videoGenerate.name;

    List<String> imagePaths = [];
    if (isVideoTask) {
      // For video generation, collect all image inputs
      final first = params['firstFramePath'] as String?;
      final last = params['lastFramePath'] as String?;
      final refs = params['referenceImagePaths'] as List<dynamic>?;

      if (first != null) imagePaths.add(first);
      if (last != null) imagePaths.add(last);
      if (refs != null) imagePaths.addAll(refs.cast<String>());
    } else {
      imagePaths = galleryState.selectedImages.map((f) => f.path).toList();
    }

    if (prompt.isEmpty && imagePaths.isEmpty) return;

    if (isVideoTask && !isVideoCompatibleModel(modelIdentifier is int ? modelIdentifier : null)) {
      addLog('Error: Selected model is not compatible with video generation.', level: 'ERROR');
      return;
    }

    params['imagePrefix'] = galleryState.imagePrefix;
    params['retryCount'] = retryCount;
    params['compressReferenceImages'] = compressReferenceImages;
    // Generation→prompt-version provenance: only while the outgoing prompt is
    // byte-for-byte (trimmed) the text the assistant staged — an edited
    // prompt is the user's own and gets no version tag. The tagged
    // parameters persist with the task, which is what lets the gallery badge
    // and the feedback dialog derive provenance after a restart.
    final provenanceParams = appliedAssistantPrompt?.taskParamsFor(prompt);
    if (provenanceParams != null) params.addAll(provenanceParams);
    // Gemini safety thresholds travel with the task so payload builders can
    // apply them per request (Map<String,String>, JSON-safe for persistence).
    params[SafetySettings.paramKey] = Map<String, String>.from(safetyThresholds);

    await taskQueue.addTask(
      imagePaths,
      modelIdentifier,
      params,
      modelIdDisplay: modelIdDisplay,
      useStream: params['useStream'] ?? useStream,
      type: params['taskType'] != null
          ? TaskType.values.firstWhere((e) => e.name == params['taskType'])
          : TaskType.imageProcess,
    );

    // Recorded only once the task is actually queued, so a rejected submit
    // doesn't leave a prompt in the history. Empty prompts are dropped by the
    // repository, which keeps image-only submissions out of the list.
    final historyType = _promptHistoryTypeFor(params['taskType'] as String?);
    if (historyType != null) {
      await recordPromptHistory(historyType, prompt);
    }

    addLog('Task submitted with ${imagePaths.length} input images.');
  }

  /// The history bucket a task's prompt belongs in, or null for task types with
  /// no prompt field of their own (rename, refine, download).
  PromptHistoryType? _promptHistoryTypeFor(String? taskType) {
    if (taskType == null || taskType == TaskType.imageProcess.name) {
      return PromptHistoryType.image;
    }
    if (taskType == TaskType.videoGenerate.name) return PromptHistoryType.video;
    return null;
  }

  Future<void> submitVideoTask(dynamic modelIdentifier, Map<String, dynamic> params, {String? modelIdDisplay}) async {
    if (!isVideoCompatibleModel(modelIdentifier is int ? modelIdentifier : null)) {
      addLog('Error: Selected model is not compatible with video generation.', level: 'ERROR');
      return;
    }

    params['taskType'] = TaskType.videoGenerate.name;
    await submitTask(modelIdentifier, params, modelIdDisplay: modelIdDisplay);
  }
}
