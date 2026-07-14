import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_image.dart';
import '../services/prompt_optimizer_agent.dart';
import '../services/repositories/assistant_session_repository.dart';

class WorkbenchUIState extends ChangeNotifier {
  WorkbenchUIState() {
    PromptOptimizerAgent.sessions[optimizerSession.id] = optimizerSession;
  }

  // Preview State
  List<AppImage> previewImages = [];
  int activePreviewIndex = 0;

  // Comparator State
  bool isComparatorOpen = false; 
  String? comparatorRawPath;
  String? comparatorAfterPath;
  bool isComparatorSyncMode = true; // true: Sync side-by-side, false: Hover swap

  // Mask Editor State
  AppImage? maskEditorSourceImage;

  // Prompt Optimizer State
  String optimizerRoughPrompt = "";
  List<AppImage> optimizerReferenceImages = [];

  /// Interactive optimizer conversation. Replaced (not mutated) when the user
  /// starts a new conversation, so widgets watching this state re-subscribe.
  PromptOptimizerSession optimizerSession = PromptOptimizerSession();

  // Optimizer Config State (persisted across tab switches)
  int? optSelectedModelDbId;
  int? optSelectedTagId;
  String? optSelectedSysPrompt;
  bool optUseCustomSysPrompt = false;

  // Video Generation State
  List<AppImage> videoReferenceImages = [];
  AppImage? videoFirstFrame;
  AppImage? videoLastFrame;
  String? lastGeneratedVideoPath;

  // Preview Methods
  void setPreviewList(List<AppImage> images, int initialIndex) {
    previewImages = List.from(images);
    activePreviewIndex = initialIndex.clamp(0, previewImages.isEmpty ? 0 : previewImages.length - 1);
    notifyListeners();
  }

  void setActivePreview(int index) {
    if (index >= 0 && index < previewImages.length) {
      activePreviewIndex = index;
      notifyListeners();
    }
  }

  void clearAllPreviews() {
    previewImages = [];
    activePreviewIndex = 0;
    notifyListeners();
  }

  // Optimizer Methods
  /// Starts a fresh optimizer conversation. The old session is deliberately
  /// not disposed — chat widgets may still be unsubscribing from it — it is
  /// simply dropped from the agent registry and garbage-collected.
  void newOptimizerSession({AssistantMode? mode}) {
    PromptOptimizerAgent.sessions.remove(optimizerSession.id);
    optimizerSession = PromptOptimizerSession(mode: mode ?? optimizerSession.mode);
    PromptOptimizerAgent.sessions[optimizerSession.id] = optimizerSession;
    notifyListeners();
  }

  AssistantMode get assistantMode => optimizerSession.mode;

  // --- Persisted assistant sessions -------------------------------------

  final AssistantSessionRepository _assistantRepo = AssistantSessionRepository();

  Future<List<AssistantSessionMeta>> listAssistantSessions() =>
      _assistantRepo.listSessions();

  Future<void> deleteAssistantSession(String id) async {
    await _assistantRepo.deleteSession(id);
    notifyListeners();
  }

  Future<void> renameAssistantSession(String id, String title) async {
    await _assistantRepo.renameSession(id, title);
    if (optimizerSession.id == id) optimizerSession.title = title;
    notifyListeners();
  }

  /// Restores a persisted conversation into the workbench. Reference images
  /// whose files vanished are dropped from the panel (a notice entry is added
  /// to the transcript); the user can re-add images and continue.
  ///
  /// Returns false when the session no longer exists.
  Future<bool> restoreAssistantSession(String id) async {
    if (optimizerSession.id == id) return true;
    final meta = await _assistantRepo.getSession(id);
    if (meta == null) return false;
    final stored = await _assistantRepo.loadMessages(id);

    final existing = <AppImage>[];
    bool anyMissing = false;
    for (final img in meta.refImages) {
      final path = img['path'];
      if (path == null) continue;
      if (File(path).existsSync()) {
        existing.add(AppImage(path: path, name: img['name'] ?? path.split(Platform.pathSeparator).last));
      } else {
        anyMissing = true;
      }
    }

    final session = PromptOptimizerSession.fromStored(
      id: meta.id,
      mode: meta.mode,
      title: meta.title,
      history: [for (final m in stored) m.message],
      hasCompactedHistory: stored.any((m) => m.isSummary),
      compactedNoticeText: PromptOptimizerAgent.compactedNoticeToken,
      missingImageNoticeText:
          anyMissing ? PromptOptimizerAgent.imageMissingNoticeToken : null,
    );

    PromptOptimizerAgent.sessions.remove(optimizerSession.id);
    optimizerSession = session;
    PromptOptimizerAgent.sessions[session.id] = session;
    optimizerReferenceImages = existing;
    notifyListeners();
    return true;
  }

  /// Switching modes always starts a fresh conversation (mode is fixed per
  /// session). Callers should confirm with the user first when the current
  /// session already has content.
  void setAssistantMode(AssistantMode mode) {
    if (optimizerSession.mode == mode) return;
    newOptimizerSession(mode: mode);
  }

  void setOptimizerModel(int? id) { optSelectedModelDbId = id; notifyListeners(); }
  void setOptimizerTag(int? id) { optSelectedTagId = id; notifyListeners(); }
  void setOptimizerSysPrompt(String? prompt) { optSelectedSysPrompt = prompt; notifyListeners(); }
  void setOptimizerSysPromptMode(bool useCustom) { optUseCustomSysPrompt = useCustom; notifyListeners(); }

  void sendToOptimizer(String prompt, List<AppImage> images) {
    optimizerRoughPrompt = prompt;
    _appendAssistantImages(images);
    notifyListeners();
  }

  /// Adds [images] to the assistant reference list, skipping duplicates
  /// (by path). Unlike the old behavior this never replaces the list — the
  /// assistant's references are managed independently of the workbench
  /// selection.
  void addAssistantImages(List<AppImage> images) {
    if (_appendAssistantImages(images)) notifyListeners();
  }

  void removeAssistantImage(AppImage image) {
    final next =
        optimizerReferenceImages.where((i) => i.path != image.path).toList();
    if (next.length == optimizerReferenceImages.length) return;
    optimizerReferenceImages = next;
    notifyListeners();
  }

  bool _appendAssistantImages(List<AppImage> images) {
    final existing = optimizerReferenceImages.map((i) => i.path).toSet();
    final added = images.where((i) => !existing.contains(i.path)).toList();
    if (added.isEmpty) return false;
    optimizerReferenceImages = [...optimizerReferenceImages, ...added];
    return true;
  }

  void clearOptimizerTransfer() {
    optimizerRoughPrompt = "";
    // Note: We might want to keep the images as reference in the sidebar
    // so we only clear the prompt "signal" that triggers the overwrite.
    notifyListeners();
  }

  // Video Methods
  void addVideoReferenceImage(AppImage image) {
    if (!videoReferenceImages.any((i) => i.path == image.path)) {
      videoReferenceImages.add(image);
      notifyListeners();
    }
  }

  void removeVideoReferenceImage(AppImage image) {
    videoReferenceImages.removeWhere((i) => i.path == image.path);
    notifyListeners();
  }

  void setVideoFirstFrame(AppImage? image) {
    videoFirstFrame = image;
    notifyListeners();
  }

  void setVideoLastFrame(AppImage? image) {
    videoLastFrame = image;
    notifyListeners();
  }

  void setLastGeneratedVideoPath(String? path) {
    lastGeneratedVideoPath = path;
    notifyListeners();
  }

  void clearVideoInputs() {
    videoReferenceImages.clear();
    videoFirstFrame = null;
    videoLastFrame = null;
    notifyListeners();
  }

  // Comparator Methods
  void sendToComparator(String path, {bool isAfter = false}) {
    if (isAfter) {
      comparatorAfterPath = path;
    } else {
      comparatorRawPath = path;
    }
    isComparatorOpen = true; // Signal that we have data
    notifyListeners();
  }

  void clearComparator() {
    comparatorRawPath = null;
    comparatorAfterPath = null;
    notifyListeners();
  }

  void toggleComparatorMode() {
    isComparatorSyncMode = !isComparatorSyncMode;
    notifyListeners();
  }

  void setMaskEditorSourceImage(AppImage? image) {
    maskEditorSourceImage = image;
    notifyListeners();
  }

  void setCropResizeSourceImage(AppImage? image) {
    cropResizeSourceImage = image;
    notifyListeners();
  }

  // Crop & Resize State
  AppImage? cropResizeSourceImage;
  double? cropAspectRatio; 
  int? targetWidth;
  int? targetHeight;
  bool maintainAspectRatio = true;
  String samplingMethod = 'lanczos';
  final GlobalKey<State> cropKey = GlobalKey<State>();

  void setCropAspectRatio(double? ratio) {
    cropAspectRatio = ratio;
    notifyListeners();
  }

  void setTargetDimensions(int? width, int? height) {
    targetWidth = width;
    targetHeight = height;
    notifyListeners();
  }

  void setMaintainAspectRatio(bool maintain) {
    maintainAspectRatio = maintain;
    notifyListeners();
  }

  void setSamplingMethod(String method) {
    samplingMethod = method;
    notifyListeners();
  }
}
