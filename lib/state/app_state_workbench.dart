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

  Future<void> updateWorkbenchConfig({
    String? modelId,
    String? prompt,
    bool? useStream,
  }) async {
    if (modelId != null) {
      lastSelectedModelId = modelId;
      await _db.saveSetting('last_model_id', modelId);
    }
    if (prompt != null) {
      lastPrompt = prompt;
      await _db.saveSetting('last_prompt', prompt);
    }
    if (useStream != null) {
      this.useStream = useStream;
      await _db.saveSetting('workbench_use_stream', useStream.toString());
    }
    notify();
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

    addLog('Task submitted with ${imagePaths.length} input images.');
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
