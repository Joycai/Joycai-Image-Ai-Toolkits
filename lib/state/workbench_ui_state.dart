import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_image.dart';
import '../models/prompt.dart';
import '../models/result_feedback.dart';
import '../models/task_item.dart';
import '../services/assistant/assistant_kb_distill.dart';
import '../services/assistant/prompt_optimizer_agent.dart';
import '../services/assistant/prompt_provenance.dart';
import '../services/db/database_service.dart';
import '../services/db/repositories/assistant_session_repository.dart';
import '../services/db/repositories/task_repository.dart';

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
  WorkbenchUIState({DatabaseService? database}) : _db = database ?? DatabaseService() {
    PromptOptimizerAgent.sessions[optimizerSession.id] = optimizerSession;
  }

  /// The database this state reads. Defaults to the app's one
  /// [DatabaseService]; a test hands in a [DatabaseService.forDatabase] over
  /// an in-memory database and needs no private data directory.
  final DatabaseService _db;

  late final TaskRepository _tasks = TaskRepository(db: _db);

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
  String optimizerRoughPrompt = '';
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

  /// What the loaded preset hands back (`A3e`). Travels with the text rather
  /// than being looked up from [optSysPromptTemplateId] at send time: the
  /// text outlives its library row — deleted, it is still what is sent — and
  /// the same text under the other kind's framing is the surprise to avoid.
  PresetOutputKind optPresetOutputKind = PresetOutputKind.prompt;

  /// [optPresetOutputKind] as it will actually be used: no text is the
  /// built-in preset, which hands back a prompt whatever was loaded before
  /// the text was cleared. What the panel shows and what a turn is queued
  /// with both read this, so they cannot disagree.
  PresetOutputKind get effectivePresetOutputKind =>
      (optSelectedSysPrompt ?? '').trim().isEmpty ? PresetOutputKind.prompt : optPresetOutputKind;

  // Video Generation State
  List<AppImage> videoReferenceImages = [];
  AppImage? videoFirstFrame;
  AppImage? videoLastFrame;
  String? lastGeneratedVideoPath;

  /// Whether a gallery card's context menu is up.
  ///
  /// The glass budget (`A1`: 「菜单打开即隐操作条」) — a desktop workbench
  /// already shows three layers (title bar, toolbar, selection bar), and the
  /// menu is a fourth; the selection bar yields to it while it is open.
  bool galleryMenuOpen = false;

  void setGalleryMenuOpen(bool open) {
    if (galleryMenuOpen == open) return;
    galleryMenuOpen = open;
    notifyListeners();
  }

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

  // Optimizer Methods
  /// Starts a fresh optimizer conversation. The old session is deliberately
  /// not disposed — chat widgets may still be unsubscribing from it — it is
  /// simply dropped from the agent registry and garbage-collected.
  void newOptimizerSession({AssistantMode? mode}) {
    PromptOptimizerAgent.sessions.remove(optimizerSession.id);
    optimizerSession = PromptOptimizerSession(mode: mode ?? optimizerSession.mode);
    PromptOptimizerAgent.sessions[optimizerSession.id] = optimizerSession;
    // A fresh session has generated nothing; no query needed.
    resultVersionByPath = const {};
    notifyListeners();
  }

  AssistantMode get assistantMode => optimizerSession.mode;

  // --- Persisted assistant sessions -------------------------------------

  late final AssistantSessionRepository _assistantRepo =
      AssistantSessionRepository(db: _db);

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
    // Cleared now, refilled asynchronously: a restored session's past
    // generations live in the tasks table, and the stale map of the previous
    // session must not badge this one's gallery while the query runs.
    resultVersionByPath = const {};
    notifyListeners();
    refreshResultProvenance();
  }

  /// Task preset ⇄ knowledge base starts a fresh conversation — callers
  /// should confirm first when the current one has content. Between the two
  /// knowledge uses the session is kept ([PromptOptimizerSession
  /// .switchKnowledgeUse]), and a switch it refuses — a turn is running — is
  /// dropped here rather than falling through to a new session.
  void setAssistantMode(AssistantMode mode) {
    final session = optimizerSession;
    if (session.mode == mode) return;
    if (session.usesKnowledgeBase && PromptOptimizerSession.isKnowledgeMode(mode)) {
      if (!session.switchKnowledgeUse(mode)) return;
      _assistantRepo.setSessionMode(session.id, mode).catchError((Object _) {
        // The next turn's sync writes the mode again; nothing to surface.
      });
      notifyListeners();
      return;
    }
    newOptimizerSession(mode: mode);
  }

  void setOptimizerModel(int? id) { optSelectedModelDbId = id; notifyListeners(); }
  void setOptimizerSysPrompt(String? prompt) { optSelectedSysPrompt = prompt; notifyListeners(); }

  /// Loads a preset — null for the built-in: its identity, the text it
  /// starts from and what it hands back. Set together, because a template id
  /// without its text would leave the panel claiming an edit the user never
  /// made, and a text without its kind would be framed as the last one's.
  void loadOptimizerPreset(SystemPrompt? preset) {
    optSysPromptTemplateId = preset?.id;
    // Empty, not null, for the built-in: null reads as "never chosen", which
    // the first load answers by picking the library's first preset.
    optSelectedSysPrompt = preset?.content ?? '';
    optPresetOutputKind = preset?.outputKind ?? PresetOutputKind.prompt;
    notifyListeners();
  }

  /// What a turn of [session] is queued with. The preset — its text and what
  /// it hands back — goes only with a task-preset session: a knowledge
  /// session's system prompt is built in.
  Map<String, dynamic> optimizerTurnParameters(PromptOptimizerSession session) => {
        'sessionId': session.id,
        'mode': session.mode.name,
        if (session.mode == AssistantMode.systemPrompt) ...{
          'systemPrompt': optSelectedSysPrompt,
          'outputKind': effectivePresetOutputKind.name,
        },
      };

  /// Follows the loaded preset's row when the library is re-read: its kind
  /// can only be changed there, and unlike its text there is no edit in this
  /// panel for the change to collide with. A row that is gone changes nothing.
  void syncOptimizerPresetKind(List<SystemPrompt> library) {
    final id = optSysPromptTemplateId;
    if (id == null) return;
    for (final p in library) {
      if (p.id != id) continue;
      if (p.outputKind == optPresetOutputKind) return;
      optPresetOutputKind = p.outputKind;
      notifyListeners();
      return;
    }
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

  /// Moves one reference image within the group the panel lets the user
  /// reorder (`A3c`).
  ///
  /// [slots] are the list positions of that group, in list order — the result
  /// images feedback turns added sit between them and keep their own
  /// positions, so their ids do not move. [from] and [to] index into [slots],
  /// with [to] already adjusted for the removal (`onReorderItem`).
  ///
  /// The list order is what the next turn sends and what the model's image
  /// ids count, the same way a removal renumbers them; nothing is sent to the
  /// model about the move. Refused while a turn runs — the panel stops the
  /// drag then, and this covers a drag already under way when the turn began.
  /// (A turn still waiting in the queue is the caller's to check: this state
  /// does not see the queue.) Returns whether the list changed.
  bool reorderAssistantReferences(List<int> slots, int from, int to) {
    if (from == to || optimizerSession.isRunning) return false;
    if (from < 0 || from >= slots.length || to < 0 || to >= slots.length) return false;
    if (slots.any((i) => i < 0 || i >= optimizerReferenceImages.length)) return false;
    final group = [for (final i in slots) optimizerReferenceImages[i]];
    group.insert(to, group.removeAt(from));
    final next = List<AppImage>.of(optimizerReferenceImages);
    for (var k = 0; k < slots.length; k++) {
      next[slots[k]] = group[k];
    }
    optimizerReferenceImages = next;
    notifyListeners();
    return true;
  }

  /// Feeds a generated result back to the assistant: the image joins the
  /// reference list (surfaced to the model as kind "result") and the user's
  /// verdict (`3b`: thumbs up/down, reason tags, an optional note) is
  /// appended as a feedback turn bound to [promptVersion] (defaulting to the
  /// latest staged version — the one the workbench generated with, in the
  /// closed-loop flow).
  ///
  /// Returns false when there is no prompt version to give feedback on. The
  /// caller still enqueues the agent turn, exactly as after a typed message.
  bool sendResultFeedback(
    AppImage image, {
    required ResultFeedback feedback,
    int? promptVersion,
  }) {
    final session = optimizerSession;
    // Never inject into a live turn: it would wedge a user message between an
    // assistant tool-call message and its results (the shape both endpoints
    // 400 on) and queue a second turn. The pill is already withdrawn while
    // running; this guards the async gap after the dialog opens. Same
    // contract as _handleAskUserAnswer / _handleOptimizerRetry.
    if (session.isRunning) return false;
    final version = promptVersion ?? session.promptVersions;
    if (version < 1) return false;
    // A feedback click while a question card is pending answers it the same
    // way free text does (mirrors _handleOptimizerSend).
    final pendingAsk = session.pendingAskUser;
    if (pendingAsk != null) {
      PromptOptimizerAgent.resolvePendingAskUserAsFreeText(
        session: session,
        callId: pendingAsk.callId,
      );
    }
    _appendAssistantImages([image]);
    session.addResultFeedback(
      imageName: image.name,
      promptVersion: version,
      feedback: feedback.note,
      satisfied: feedback.satisfied,
      reasons: feedback.satisfied ? const [] : feedback.reasons,
    );
    _assistantTurnRequested = true;
    notifyListeners();
    return true;
  }

  /// `result path → prompt version` for the LIVE assistant session — what the
  /// gallery's version badge and the feedback dialog's binding read.
  ///
  /// A projection of the tasks table (whose parameters carry the provenance
  /// tags `submitTask` wrote), rebuilt on session switch and appended to as
  /// results land. Never persisted on its own: the tasks table is the record,
  /// this map is its index for the one session on screen.
  Map<String, int> resultVersionByPath = const {};

  /// Rebuilds [resultVersionByPath] from stored tasks for the live session.
  Future<void> refreshResultProvenance() async {
    final sessionId = optimizerSession.id;
    Map<String, int> versions;
    try {
      versions = PromptProvenance.resultVersionsFromTasks(
        await _tasks.getTasksForAssistantSession(sessionId),
        sessionId,
      );
    } catch (_) {
      // No database (tests) or a corrupt row — the badge is a convenience,
      // not something worth failing a session switch over.
      versions = const {};
    }
    // The session may have been switched again while the query ran.
    if (optimizerSession.id != sessionId) return;
    resultVersionByPath = versions;
    notifyListeners();
  }

  /// The generation task that produced the result at [path] in the live
  /// session, or null when none is on record (no database, or a picture
  /// that came from elsewhere). The feedback dialog's heading (`3b`) names
  /// the run from it — model and time — beside the version.
  ///
  /// Read from the tasks table on demand rather than cached beside
  /// [resultVersionByPath]: it is one row per dialog open, and keeping a
  /// second projection in step would cost more than the query.
  Future<TaskItem?> resultTaskForPath(String path) async {
    if (!resultVersionByPath.containsKey(path)) return null;
    final sessionId = optimizerSession.id;
    try {
      final tasks = await _tasks.getTasksForAssistantSession(sessionId);
      TaskItem? found;
      for (final task in tasks) {
        if (task.parameters[PromptProvenance.sessionParamKey] != sessionId) continue;
        // Later rows win, as they do in resultVersionsFromTasks.
        if (task.resultPaths.contains(path)) found = task;
      }
      return found;
    } catch (_) {
      return null;
    }
  }

  /// Records one freshly generated result, from the task-event stream.
  void recordResultProvenance(String path, int version) {
    if (resultVersionByPath[path] == version) return;
    resultVersionByPath = {...resultVersionByPath, path: version};
    notifyListeners();
  }

  /// Set when something outside the assistant screen (the gallery card's
  /// feedback dialog) staged a turn that should run now. The workbench screen
  /// listens and, on true, runs its usual enqueue path — the guards (model
  /// picked, knowledge base valid) live there, next to their snackbars.
  ///
  /// A latch rather than a callback registration: the state must not hold a
  /// closure over a screen's context, and a consumed latch cannot fire twice.
  bool _assistantTurnRequested = false;

  /// Returns whether a turn was requested, clearing the latch.
  bool takeAssistantTurnRequest() {
    if (!_assistantTurnRequested) return false;
    _assistantTurnRequested = false;
    return true;
  }

  /// Stages a "distill this session into the knowledge base" request on the
  /// live session. The caller enqueues the agent turn on
  /// [KbDistillStageResult.staged] and surfaces the other outcomes.
  Future<KbDistillStageResult> requestKbDistill() async {
    final result =
        await AssistantKbDistill.stageKbDistillRequest(session: optimizerSession);
    if (result == KbDistillStageResult.staged) notifyListeners();
    return result;
  }

  bool _appendAssistantImages(List<AppImage> images) {
    final existing = optimizerReferenceImages.map((i) => i.path).toSet();
    final added = images.where((i) => !existing.contains(i.path)).toList();
    if (added.isEmpty) return false;
    optimizerReferenceImages = [...optimizerReferenceImages, ...added];
    return true;
  }

  void clearOptimizerTransfer() {
    optimizerRoughPrompt = '';
    // Note: We might want to keep the images as reference in the sidebar
    // so we only clear the prompt "signal" that triggers the overwrite.
    notifyListeners();
  }

  // Video Methods
  void addVideoReferenceImage(AppImage image) {
    if (!videoReferenceImages.any((i) => i.path == image.path)) {
      videoReferenceImages = [...videoReferenceImages, image];
      notifyListeners();
    }
  }

  void removeVideoReferenceImage(AppImage image) {
    if (!videoReferenceImages.any((i) => i.path == image.path)) return;
    videoReferenceImages = videoReferenceImages
        .where((i) => i.path != image.path)
        .toList();
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
