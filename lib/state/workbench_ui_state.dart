import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_image.dart';
import '../services/prompt_optimizer_agent.dart';
import '../services/repositories/assistant_session_repository.dart';

/// How the comparator arranges the two images.
///
/// Was a single `isComparatorSyncMode` boolean, which could only say
/// "side-by-side" or "curtain" — the design spec's third arrangement (one
/// above the other, for landscape pairs a horizontal split squeezes) had
/// nowhere to live.
enum ComparatorLayout {
  /// Two panes across, before on the left.
  sideBySide,

  /// Two panes down, before on top. For wide images, where a vertical split
  /// leaves each half too narrow to judge.
  stacked,

  /// One image over the other, revealed by a draggable curtain.
  slider,
}

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
  ComparatorLayout comparatorLayout = ComparatorLayout.sideBySide;

  /// Whether the two panes share one zoom/pan transform. Off, each pane is
  /// navigated on its own — which is what you want when the pair is framed
  /// differently and matching the crops by hand is the point.
  ///
  /// Meaningless in [ComparatorLayout.slider], where both layers are the same
  /// transform by construction.
  bool comparatorSyncTransform = true;

  /// Whether the metadata panel is showing. Desktop only: on narrow widths the
  /// panel is a drawer, which has its own open/closed state.
  bool comparatorShowMetadata = true;

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

  /// The system prompt actually sent, which is the editor's text — not the
  /// template's. `10g` lets the user edit a template in place without
  /// committing the edit back to the library, so the two do diverge.
  String? optSelectedSysPrompt;

  /// Which library template [optSelectedSysPrompt] was loaded from, or null
  /// when the text belongs to no template.
  ///
  /// Tracked separately rather than recovered by matching the text against the
  /// library: the moment the user types a character the text matches nothing,
  /// and that is exactly the state — "edited, unsaved" — that has to be able
  /// to name the template it came from.
  int? optSysPromptTemplateId;

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

    adoptOptimizerSession(session, existing);
    return true;
  }

  /// Makes [session] the live one, replacing whatever was open.
  ///
  /// The registry swap is the part that matters: [PromptOptimizerAgent] looks
  /// sessions up by id, so dropping the outgoing one and registering the
  /// incoming one has to happen together with the field assignment or a turn
  /// started afterwards writes into a session nothing is rendering.
  void adoptOptimizerSession(
    PromptOptimizerSession session,
    List<AppImage> references,
  ) {
    PromptOptimizerAgent.sessions.remove(optimizerSession.id);
    optimizerSession = session;
    PromptOptimizerAgent.sessions[session.id] = session;
    optimizerReferenceImages = references;
    notifyListeners();
  }

  /// Switching modes always starts a fresh conversation (mode is fixed per
  /// session). Callers should confirm with the user first when the current
  /// session already has content.
  void setAssistantMode(AssistantMode mode) {
    if (optimizerSession.mode == mode) return;
    newOptimizerSession(mode: mode);
  }

  void setOptimizerModel(int? id) { optSelectedModelDbId = id; notifyListeners(); }
  void setOptimizerSysPrompt(String? prompt) { optSelectedSysPrompt = prompt; notifyListeners(); }

  /// Loads a library template: both the identity and the text it starts from.
  /// Set together, because a template id without its text would leave the
  /// panel claiming an edit the user never made.
  void setOptimizerSysPromptTemplate(int? id, String? content) {
    optSysPromptTemplateId = id;
    optSelectedSysPrompt = content;
    notifyListeners();
  }

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

  void setComparatorLayout(ComparatorLayout layout) {
    if (comparatorLayout == layout) return;
    comparatorLayout = layout;
    notifyListeners();
  }

  void toggleComparatorSyncTransform() {
    comparatorSyncTransform = !comparatorSyncTransform;
    notifyListeners();
  }

  void toggleComparatorMetadata() {
    comparatorShowMetadata = !comparatorShowMetadata;
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

  /// The selection's size in source pixels, as the canvas currently has it.
  ///
  /// Published by the view because only it receives the editor's change
  /// callback, and read by the toolbar so the width/height fields can stand at
  /// the real numbers instead of empty placeholders. Two widgets, one fact —
  /// it cannot live in either of them.
  Size? cropPixelSize;

  void setCropPixelSize(Size? size) {
    if (cropPixelSize == size) return;
    cropPixelSize = size;
    notifyListeners();
  }

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
