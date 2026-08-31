import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_paths.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/llm_model.dart';
import '../../models/prompt.dart';
import '../../services/assistant_kb_distill.dart';
import '../../services/knowledge_base_service.dart';
import '../../services/knowledge_base_starter.dart';
import '../../services/prompt_optimizer_agent.dart';
import '../../services/prompt_provenance.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_run_console.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/drawing_canvas.dart';
import '../../widgets/unified_sidebar.dart';
import '../prompts/widgets/prompt_dialogs.dart';
import 'gallery.dart';
import 'widgets/comparator_toolbar.dart';
import 'widgets/comparator_view.dart';
import 'widgets/crop_resize_toolbar.dart';
import 'widgets/crop_resize_view.dart';
import 'widgets/gallery_toolbar.dart';
import 'widgets/mask_editor_toolbar.dart';
import 'widgets/mask_editor_view.dart';
import 'widgets/metadata_inspector.dart';
import 'widgets/optimizer_config_panel.dart';
import 'widgets/optimizer_left_panel.dart';
import 'widgets/prompt_optimizer_toolbar.dart';
import 'widgets/prompt_optimizer_view.dart';
import 'widgets/video_config_panel.dart';
import 'widgets/video_workbench_view.dart';
import 'widgets/workbench_top_bar.dart';
import 'workbench_config_panel.dart';
import 'workbench_layout.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppState? _appState;
  WorkbenchUIState? _workbenchUIState;
  int _lastKnownTabIndex = 0;
  StreamSubscription? _taskSubscription;

  // Mask Editor State
  final List<DrawingPath> _maskPaths = [];
  Color _maskSelectedColor = Colors.white;
  double _maskBrushSize = 20.0;
  double _maskOpacity = 1.0;
  bool _maskIsBinaryMode = false;
  final GlobalKey _maskRepaintKey = GlobalKey();

  /// Bumped whenever [_maskPaths] changes in a way only the canvas cares
  /// about, and where the pointer is.
  ///
  /// Both used to be plain fields updated through `setState`, and `setState`
  /// here rebuilds the *screen*: the top bar, the mask toolbar and the whole
  /// canvas subtree. `onHover` fires once per mouse move — 120 times a second
  /// on a fast display — so moving the pointer across the canvas rebuilt the
  /// entire workbench at pointer rate to move a brush-preview circle. The
  /// canvas subscribes to these instead and repaints on its own; the screen
  /// still rebuilds once per stroke, which is what the toolbar's undo/clear
  /// enablement needs and no more.
  final ValueNotifier<int> _maskRevision = ValueNotifier<int>(0);
  final ValueNotifier<Offset?> _maskMouse = ValueNotifier<Offset?>(null);
  
  // Prompt Optimizer State
  final TextEditingController _optInputCtrl = TextEditingController();
  /// Every refiner template in the library. `10g` picks from all of them —
  /// the tag-filtered subset the old two-dropdown form needed went with it.
  List<SystemPrompt> _optSysPrompts = [];
  bool _optIsLoadingData = true;
  KbStatus _kbStatus = KbStatus.notSet;
  String? _kbPath;
  KbWritePolicy _kbWritePolicy = KbWritePolicy.defaults;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appState == null) {
      _appState = Provider.of<AppState>(context, listen: false);
      _initTabController();
      
      _appState!.addListener(_onAppStateChanged);
      
      // Listen for manual data send from UI State
      _workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
      _workbenchUIState!.addListener(_onWorkbenchUIChanged);
      
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      _taskSubscription?.cancel();
      _taskSubscription = taskService.eventStream.listen(_onTaskEvent);
      
      _loadOptimizerData();
    }
  }

  void _onTaskEvent(TaskEvent event) {
    if (event.type != TaskEventType.imageResult || !mounted) return;
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    if (event.taskType == TaskType.videoGenerate) {
      uiState.setLastGeneratedVideoPath(event.data as String);
    }

    // Provenance hand-off #3, live half: a result of a task tagged with the
    // on-screen session gets its version into the badge map the moment it
    // lands — the stored half (refreshResultProvenance) covers restarts.
    //
    // Only a session that has staged a prompt version can own a tagged task
    // (the tag is written when an *applied* assistant prompt is generated
    // with), so skip the queue scan entirely for the common case — a plain
    // generation with no assistant loop engaged — rather than walking the
    // queue on every image result to discard the untagged task it finds.
    final session = uiState.optimizerSession;
    if (session.promptVersions == 0) return;
    final taskService = Provider.of<TaskQueueService>(context, listen: false);
    final task = taskService.queue
        .cast<TaskItem?>()
        .firstWhere((t) => t!.id == event.taskId, orElse: () => null);
    if (task == null) return;
    if (task.parameters[PromptProvenance.sessionParamKey] != session.id) {
      return;
    }
    final version = PromptProvenance.decodeVersionParam(task.parameters);
    if (version != null) {
      uiState.recordResultProvenance(event.data as String, version);
    }
  }

  void _onWorkbenchUIChanged() {
    if (!mounted) return;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);

    // If we have a fresh manual data transfer
    if (workbenchUIState.optimizerRoughPrompt.isNotEmpty) {
      setState(() {
        _optInputCtrl.text = workbenchUIState.optimizerRoughPrompt;
        // The images are used by the sidebar reference panel via Provider
      });
      // Reset the trigger in UI State to prevent overwriting on subsequent refreshes
      workbenchUIState.clearOptimizerTransfer();
    }

    // A turn staged outside this screen (the gallery card's feedback dialog).
    // The guards live in the runner, next to their snackbars — consuming the
    // latch here only decides *that* a turn was asked for.
    if (workbenchUIState.takeAssistantTurnRequest()) {
      _runRequestedAssistantTurn(workbenchUIState);
    }
  }

  /// Runs a turn some other surface already staged into the session — same
  /// guards as [_handleOptimizerSend], minus the composer text.
  Future<void> _runRequestedAssistantTurn(WorkbenchUIState workbenchUIState) async {
    final l10n = AppLocalizations.of(context)!;
    final session = workbenchUIState.optimizerSession;

    // A turn already in flight owns the session; starting a second one would
    // corrupt its history. Same guard as _handleAskUserAnswer / _handleRetry.
    if (session.isRunning) return;
    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }
    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Stages the distill request (`20d`) and runs it as a normal agent turn.
  Future<void> _handleKbDistill() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    await _refreshKbStatus();
    if (_kbStatus != KbStatus.ok) {
      if (mounted) {
        AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
      }
      return;
    }

    final result = await workbenchUIState.requestKbDistill();
    if (!mounted) return;
    switch (result) {
      case KbDistillStageResult.staged:
        await _enqueueAssistantTurn(workbenchUIState, session);
      case KbDistillStageResult.nothingToDistill:
        AppSnackBar.warning(context, l10n.optDistillDisabledTooltip);
      case KbDistillStageResult.alreadyPending:
        AppSnackBar.warning(context, l10n.optDistillAlreadyPending);
      case KbDistillStageResult.busy:
      case KbDistillStageResult.notKnowledgeSession:
        break; // The chip is hidden/disabled in these states; nothing to say.
    }
  }

  /// Opens the prompt-library save dialog prefilled with the final staged
  /// prompt (`20d`·d). The dialog owns persistence, like every prompt edit.
  Future<void> _handleSaveFinalPrompt() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    final refined = session.refinedPrompt;
    final appState = _appState;
    if (refined == null || appState == null) return;

    final prompts = await appState.getPrompts();
    final tags = await appState.getPromptTags();
    if (!mounted) return;
    await showPromptEditDialog(
      context,
      l10n,
      userPrompts: prompts,
      tags: tags,
      initialTitle: session.title,
      initialContent: refined,
    );
  }

  // Optimizer Helpers
  Future<void> _refreshKbStatus() async {
    final kb = KnowledgeBaseService();
    final path = await kb.getRoot();
    final status = await kb.validate(path);
    final policy = await kb.getWritePolicy();
    if (mounted) {
      setState(() {
        _kbPath = path;
        _kbStatus = status;
        _kbWritePolicy = policy;
      });
    }
  }

  /// Persists a change to `10h`'s write switches, then re-reads so the panel
  /// shows what is actually stored rather than what was asked for.
  Future<void> _handleWritePolicyChanged(KbWritePolicy policy) async {
    setState(() => _kbWritePolicy = policy);
    await KnowledgeBaseService().setWritePolicy(policy);
  }

  Future<void> _loadOptimizerData() async {
    if (_appState == null) return;
    await _refreshKbStatus();
    try {
      final refinerPrompts = await _appState!.getSystemPrompts(type: 'refiner');

      if (mounted) {
        final wuiState = Provider.of<WorkbenchUIState>(context, listen: false);
        setState(() {
          _optSysPrompts = refinerPrompts;

          // Only set defaults on first load; preserve user's previous selections.
          if (wuiState.optSelectedModelDbId == null && _appState!.multimodalModels.isNotEmpty) {
            wuiState.setOptimizerModel(_appState!.multimodalModels.first.id);
          }
          if (wuiState.optSelectedSysPrompt == null && refinerPrompts.isNotEmpty) {
            final first = refinerPrompts.first;
            wuiState.setOptimizerSysPromptTemplate(first.id, first.content);
          }
          _optIsLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _optIsLoadingData = false);
    }
  }

  /// Writes `10g`'s edited system prompt back over the template it came from.
  ///
  /// The library is the only place a system prompt can be *kept*: the panel's
  /// text lives on [WorkbenchUIState], which is cleared when the app closes,
  /// so an edit the user wants to keep has nowhere else to go. Tags are passed
  /// through unchanged — this saves the wording, not the filing.
  Future<void> _handleSaveSysPromptTemplate(SystemPrompt template, String content) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _appState!.updateSystemPrompt(
        template.id!,
        {
          'title': template.title,
          'content': content,
          'type': template.type,
          'is_markdown': template.isMarkdown ? 1 : 0,
          'sort_order': template.sortOrder,
        },
        tagIds: [for (final t in template.tags) if (t.id != null) t.id!],
      );
      // Re-read rather than patch the local copy: the saved row is now what
      // "unsaved" is measured against, and a stale in-memory template would
      // leave the badge showing an edit that is already on disk.
      final refreshed = await _appState!.getSystemPrompts(type: 'refiner');
      if (!mounted) return;
      setState(() => _optSysPrompts = refreshed);
      AppSnackBar.success(context, l10n.optSysPromptSaved);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, e.toString());
    }
  }

  /// Whether a turn of [session] is queued or running.
  ///
  /// Read straight off the queue rather than through the `Selector` the centre
  /// column uses — the right panel is built from a different callback, outside
  /// that builder's scope — and without subscribing to it, because the panel
  /// is rebuilt by the session's own notifications and subscribing here would
  /// hand it every unrelated task's 500ms progress tick. The cost is that the
  /// brief queued-but-not-yet-started window is not repainted for: the panel
  /// catches up when `isRunning` flips, which is when it has something new to
  /// say anyway.
  bool _optRunningForSession(PromptOptimizerSession session) {
    if (session.isRunning) return true;
    final queue = Provider.of<TaskQueueService>(context, listen: false).queue;
    return queue.any((t) =>
        t.type == TaskType.promptRefine &&
        t.parameters['sessionId'] == session.id &&
        (t.status == TaskStatus.pending || t.status == TaskStatus.processing));
  }

  /// Sends one user turn of the optimizer conversation: the message is added
  /// to the session immediately (so it shows in the chat), then a queue task
  /// runs the agent turn against the current reference images.
  Future<void> _handleOptimizerSend() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final text = _optInputCtrl.text.trim();
    if (text.isEmpty) return;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }

    final session = workbenchUIState.optimizerSession;

    // Knowledge modes require a valid knowledge base before sending.
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }

    // Free text while a question card is pending answers it: pair the
    // dangling ask_user call first so the history the turn sends is valid,
    // then let the reply flow in as a normal user turn.
    final pendingAsk = session.pendingAskUser;
    if (pendingAsk != null) {
      PromptOptimizerAgent.resolvePendingAskUserAsFreeText(
        session: session,
        callId: pendingAsk.callId,
      );
    }

    session.addUserTurn(text);
    _optInputCtrl.clear();

    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Sends the structured answers of an ask_user card and resumes the agent.
  Future<void> _handleAskUserAnswer(String callId, List<AskUserAnswer> answers) async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    if (session.isRunning) return;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }

    PromptOptimizerAgent.answerAskUser(session: session, callId: callId, answers: answers);
    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Re-runs the agent turn after a failure. The pending user message and any
  /// completed tool results are still in the session history, so nothing has
  /// to be typed or re-read again.
  Future<void> _handleOptimizerRetry() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    if (session.isRunning || session.history.isEmpty) return;

    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      AppSnackBar.warning(context, l10n.noModelsConfigured);
      return;
    }
    if (session.usesKnowledgeBase) {
      await _refreshKbStatus();
      if (_kbStatus != KbStatus.ok) {
        if (mounted) {
          AppSnackBar.warning(context, AppLocalizations.of(context)!.optKbNotConfigured);
        }
        return;
      }
    }

    await _enqueueAssistantTurn(workbenchUIState, session);
  }

  /// Stops the turn in flight, from `10i`'s 中断 button or the Esc key.
  ///
  /// Cancelling the *task* rather than reaching into the session: the queue
  /// owns the run, and it is what threads the cancellation flag the agent's
  /// tool loop already polls between batches. Nothing is rolled back — the
  /// steps that did complete stay in the transcript, which is what makes a
  /// stopped turn something the user can read rather than an erased one.
  Future<void> _handleOptimizerAbort(String taskId) async {
    final taskService = Provider.of<TaskQueueService>(context, listen: false);
    await taskService.cancelTask(taskId);
  }

  Future<void> _enqueueAssistantTurn(
    WorkbenchUIState workbenchUIState,
    PromptOptimizerSession session,
  ) async {
    // Read here rather than when the session was created: the switches live in
    // settings, the session can outlive several changes to them, and the
    // question the policy answers is about the turn now going out.
    session.writePolicy = _kbWritePolicy;
    try {
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      await taskService.addTask(
        workbenchUIState.optimizerReferenceImages.map((f) => f.path).toList(),
        workbenchUIState.optSelectedModelDbId!,
        {
          'sessionId': session.id,
          'mode': session.mode.name,
          if (session.mode == AssistantMode.systemPrompt)
            'systemPrompt': workbenchUIState.optSelectedSysPrompt,
        },
        type: TaskType.promptRefine,
        useStream: false,
        id: const Uuid().v4(),
      );
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppSnackBar.error(context, l10n.refineFailed(e.toString()));
      }
    }
  }

  /// Bottom sheet listing persisted assistant conversations with restore /
  /// rename / delete actions.
  Future<void> _showAssistantHistory() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final sessions = await workbenchUIState.listAssistantSessions();
    if (!mounted) return;
    if (sessions.isEmpty) {
      AppSnackBar.info(context, l10n.optNoHistory);
      return;
    }
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sessions.length,
            itemBuilder: (itemContext, index) {
              final meta = sessions[index];
              final isCurrent = meta.id == workbenchUIState.optimizerSession.id;
              final colorScheme = Theme.of(itemContext).colorScheme;
              return ListTile(
                dense: true,
                selected: isCurrent,
                leading: Icon(
                  switch (meta.mode) {
                    AssistantMode.knowledgeBase => Icons.menu_book_outlined,
                    AssistantMode.knowledgeEdit => Icons.edit_note_outlined,
                    AssistantMode.systemPrompt => Icons.tune,
                  },
                  size: 18,
                ),
                title: Text(
                  (meta.title == null || meta.title!.isEmpty) ? meta.id : meta.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  meta.updatedAt.toLocal().toString().substring(0, 16),
                  style: Theme.of(context).textTheme.labelMedium?.metricsOnly,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: l10n.rename,
                      onPressed: () async {
                        final ctrl = TextEditingController(text: meta.title ?? '');
                        final newTitle = await AppDialog.show<String>(
                          sheetContext,
                          title: l10n.rename,
                          content: TextField(controller: ctrl, autofocus: true),
                          actions: [
                            AppButton(
                              label: l10n.cancel,
                              variant: AppButtonVariant.text,
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                            AppButton(
                              label: l10n.confirm,
                              onPressed: () => Navigator.pop(sheetContext, ctrl.text.trim()),
                            ),
                          ],
                        );
                        if (newTitle != null && newTitle.isNotEmpty) {
                          await workbenchUIState.renameAssistantSession(meta.id, newTitle);
                          final refreshed = await workbenchUIState.listAssistantSessions();
                          sessions..clear()..addAll(refreshed);
                          setSheetState(() {});
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                      tooltip: l10n.delete,
                      onPressed: () async {
                        final confirmed = await AppDialog.show<bool>(
                          sheetContext,
                          content: Text(l10n.optDeleteSessionConfirm),
                          actions: [
                            AppButton(
                              label: l10n.cancel,
                              variant: AppButtonVariant.text,
                              onPressed: () => Navigator.pop(sheetContext, false),
                            ),
                            AppButton(
                              label: l10n.delete,
                              onPressed: () => Navigator.pop(sheetContext, true),
                            ),
                          ],
                        );
                        if (confirmed == true) {
                          await workbenchUIState.deleteAssistantSession(meta.id);
                          sessions.removeAt(index);
                          setSheetState(() {});
                        }
                      },
                    ),
                  ],
                ),
                onTap: isCurrent
                    ? null
                    : () async {
                        Navigator.pop(sheetContext);
                        await workbenchUIState.restoreAssistantSession(meta.id);
                      },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleAssistantModeChange(AssistantMode next) async {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final session = workbenchUIState.optimizerSession;
    if (session.mode == next) return;
    if (session.transcript.isNotEmpty) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await AppDialog.show<bool>(
        context,
        content: Text(l10n.optModeSwitchConfirm),
        actions: [
          AppButton(
            label: l10n.cancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(label: l10n.confirm, onPressed: () => Navigator.pop(context, true)),
        ],
      );
      if (confirmed != true) return;
    }
    workbenchUIState.setAssistantMode(next);
  }

  /// Ensures a usable knowledge-base root, then initializes it with the starter
  /// files. Only ever acts on a folder that is not already a knowledge base —
  /// the button is disabled at [KbStatus.ok], and both the picker path below
  /// and [KnowledgeBaseStarter.scaffold] re-check independently.
  Future<void> _handleScaffoldKb() async {
    final l10n = AppLocalizations.of(context)!;
    final kb = KnowledgeBaseService();
    var stored = await kb.getRoot();

    // No folder yet, or the stored one is gone: ask where to put it rather than
    // silently recreating a directory the user may have deliberately moved.
    if (stored == null || !Directory(stored).existsSync()) {
      final picked = await FilePicker.getDirectoryPath();
      if (picked == null) return;
      await kb.setRoot(picked);
      stored = picked;
    }
    final root = stored;

    // The status that enabled the button describes the *previous* root. A
    // freshly picked folder may already be someone's knowledge base, so refuse
    // before touching it — with a real explanation rather than a raw error.
    if (KnowledgeBaseStarter.isInitialized(root)) {
      await _refreshKbStatus();
      if (!mounted) return;
      AppSnackBar.info(context, l10n.kbScaffoldAlreadyInit(KnowledgeBaseService.entryFileName));
      return;
    }

    if (!mounted) return;
    final confirmed = await AppDialog.show<bool>(
      context,
      content: Text(l10n.kbScaffoldConfirm(root)),
      actions: [
        AppButton(
          label: l10n.cancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(label: l10n.confirm, onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (confirmed != true) return;

    try {
      final result = await KnowledgeBaseStarter.scaffold(root);
      await _refreshKbStatus();
      if (!mounted) return;
      AppSnackBar.success(context, l10n.kbScaffoldDone(result.created.length));
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, l10n.kbScaffoldFailed('$e'));
    }
  }

  Future<void> _handleKbEditApply(PromptOptimizerSession session, String editId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await PromptOptimizerAgent.applyStagedKbEdit(session: session, editId: editId);
      // Writing README.md can flip missingEntry -> ok, which re-enables the
      // knowledge modes in the config panel.
      await _refreshKbStatus();
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, l10n.kbEditFailed('$e'));
    }
  }

  void _handleKbEditReject(PromptOptimizerSession session, String editId) {
    PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: editId);
  }

  /// `10h`'s 全部写入 / 全部丢弃.
  ///
  /// The ids are collected before anything is answered, because resolving one
  /// edit rebuilds the transcript and iterating the live list while it changes
  /// underneath would skip half of them. Writes go one at a time and in order,
  /// so a failure part-way leaves the edits before it on disk and the rest
  /// still pending — which is what the cards will then show.
  Future<void> _handleKbEditApplyAll(PromptOptimizerSession session) async {
    final ids = [
      for (final e in PromptOptimizerAgent.pendingKbEdits(session)) e.editId!,
    ];
    for (final id in ids) {
      if (!mounted) return;
      await _handleKbEditApply(session, id);
    }
  }

  void _handleKbEditRejectAll(PromptOptimizerSession session) {
    for (final e in PromptOptimizerAgent.pendingKbEdits(session).toList()) {
      PromptOptimizerAgent.rejectStagedKbEdit(session: session, editId: e.editId!);
    }
  }

  void _handleOptimizerApply(String prompt) {
    if (_appState == null || prompt.isEmpty) return;
    // Provenance hand-off #1: remember which version this text is, so a
    // generation run with it unchanged can be tagged. The version is looked
    // up by text rather than taken as "the latest" — every prompt card has
    // its own apply button, so the user can apply v2 after v3 exists.
    final session =
        Provider.of<WorkbenchUIState>(context, listen: false).optimizerSession;
    final version =
        PromptProvenance.versionForPromptText(session.transcript, prompt);
    _appState!.appliedAssistantPrompt = version == null
        ? null
        : AppliedAssistantPrompt(
            sessionId: session.id, version: version, text: prompt);
    _appState!.updateWorkbenchConfig(prompt: prompt);
    _appState!.setWorkbenchTab(0);
    AppSnackBar.info(context, AppLocalizations.of(context)!.promptApplied);
  }

  void _onAppStateChanged() {
    if (!mounted || _appState == null) return;
    
    if (_appState!.workbenchTabIndex != _lastKnownTabIndex) {
      _lastKnownTabIndex = _appState!.workbenchTabIndex;
      final targetIndex = _lastKnownTabIndex.clamp(0, _tabController.length - 1);
      if (_tabController.index != targetIndex) {
         _tabController.index = targetIndex;
      }
      
      // Re-validate the knowledge base whenever the assistant tab is opened
      // (the user may have just changed the folder in Settings).
      if (_tabController.index == 4) _refreshKbStatus();
    }
  }

  // Mask Editor Helpers
  // Both go through setState as well as the revision: they change whether the
  // toolbar's undo and clear are enabled, which is drawn from this build.
  void _handleMaskUndo() => setState(() {
        if (_maskPaths.isNotEmpty) {
          _maskPaths.removeLast();
          _maskRevision.value++;
        }
      });

  void _handleMaskClear() => setState(() {
        _maskPaths.clear();
        _maskRevision.value++;
      });
  
  Future<void> _handleMaskSave({bool binary = false, bool selectAfterSave = true}) async {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final sourceImage = workbenchUIState.maskEditorSourceImage;
    if (sourceImage == null || _appState == null) return;

    final originalBinaryMode = _maskIsBinaryMode;
    if (binary != _maskIsBinaryMode) {
      setState(() => _maskIsBinaryMode = binary);
      // Wait for the frame that carries the mode flip — endOfFrame is the
      // actual thing being waited on; the 50ms this replaced was a guess at
      // it, and sat between the user's Save and any feedback.
      await WidgetsBinding.instance.endOfFrame;
    }

    try {
      RenderRepaintBoundary? boundary = _maskRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      
      // Get image dimensions to maintain resolution
      final bytes = await File(sourceImage.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      double pixelRatio = img.width / boundary.size.width;
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await AppPaths.getTempDirectory();
      final maskDir = Directory(p.join(tempDir, 'joycai', 'masks'));
      if (!maskDir.existsSync()) maskDir.createSync(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final prefix = binary ? 'mask_only' : 'mask';
      final fileName = '${prefix}_${p.basenameWithoutExtension(sourceImage.path)}_$timestamp.png';
      final filePath = p.join(maskDir.path, fileName);
      
      await File(filePath).writeAsBytes(pngBytes);

      if (Platform.isIOS) {
        try {
          await Gal.putImage(filePath);
        } catch (_) {}
      }

      final maskFile = AppImage(path: filePath, name: fileName);
      _appState!.galleryState.addDroppedFiles([maskFile]);
      
      if (selectAfterSave) {
        _appState!.galleryState.toggleImageSelection(maskFile);
        _appState!.galleryState.setViewMode(GalleryViewMode.temp);
        _appState!.setWorkbenchTab(0); // Return to gallery
      }

      if (mounted) {
        AppSnackBar.success(context, AppLocalizations.of(context)!.maskSaved);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, AppLocalizations.of(context)!.maskSaveError(e.toString()));
      }
    } finally {
      if (binary != originalBinaryMode && mounted) {
        setState(() => _maskIsBinaryMode = originalBinaryMode);
      }
    }
  }

  void _initTabController() {
    if (_appState == null) return;
    _lastKnownTabIndex = _appState!.workbenchTabIndex.clamp(0, AppConstants.workbenchTabCount - 1);

    _tabController = TabController(length: AppConstants.workbenchTabCount, vsync: this, initialIndex: _lastKnownTabIndex);
    
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index != _lastKnownTabIndex) {
          _lastKnownTabIndex = _tabController.index;
          _appState!.setWorkbenchTab(_tabController.index);
        }
      }
    });
  }

  @override
  void dispose() {
    _optInputCtrl.dispose();
    _appState?.removeListener(_onAppStateChanged);
    _workbenchUIState?.removeListener(_onWorkbenchUIChanged);
    _taskSubscription?.cancel();
    _tabController.dispose();
    _maskRevision.dispose();
    _maskMouse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isNarrow = Responsive.isNarrow(context);

    // Determine content based on active tab
    Widget centerContent;
    Widget leftPanel = const UnifiedSidebar();
    bool showLeftPanel = appState.isSidebarExpanded;
    bool showRightPanel = !isNarrow;

    // Bare over the window backdrop unless a tab asks otherwise — see
    // [WorkbenchLayout.centerGround].
    Color? centerGround;

    switch (appState.workbenchTabIndex) {
      case 0: // Image Processing
        centerContent = const Column(
          children: [
            GalleryToolbar(),
            Expanded(child: Gallery()),
          ],
        );
        showRightPanel = !isNarrow; // Only show on desktop by default
        break;
      case 1: // Comparator
        centerContent = const Column(
          children: [
            ComparatorToolbar(),
            Expanded(child: ComparatorView()),
          ],
        );
        // The toolbar's metadata button switches this on desktop; on narrow
        // the panel is a drawer the same button opens instead.
        showRightPanel = !isNarrow && context.watch<WorkbenchUIState>().comparatorShowMetadata;
        showLeftPanel = false; // Auto-hide sidebar
        break;
      case 2: // Mask Editor
        centerContent = Column(
          children: [
            MaskEditorToolbar(
              onUndo: _handleMaskUndo,
              onClear: _handleMaskClear,
              onSave: () => _handleMaskSave(selectAfterSave: false),
              onSaveMask: () => _handleMaskSave(binary: true, selectAfterSave: false),
              onColorChanged: (c) => setState(() => _maskSelectedColor = c),
              onBrushSizeChanged: (s) => setState(() => _maskBrushSize = s),
              onOpacityChanged: (o) => setState(() => _maskOpacity = o),
              onToggleBinary: () => setState(() => _maskIsBinaryMode = !_maskIsBinaryMode),
              selectedColor: _maskSelectedColor,
              brushSize: _maskBrushSize,
              opacity: _maskOpacity,
              isBinaryMode: _maskIsBinaryMode,
              hasPaths: _maskPaths.isNotEmpty,
            ),
            Expanded(
              child: MaskEditorView(
                paths: _maskPaths,
                revision: _maskRevision,
                selectedColor: _maskSelectedColor.withValues(alpha: _maskOpacity),
                brushSize: _maskBrushSize,
                isBinaryMode: _maskIsBinaryMode,
                repaintKey: _maskRepaintKey,
                mousePosition: _maskMouse,
                // No setState: the canvas listens to the notifier. This is the
                // callback that fires on every mouse move.
                onHover: (pos) => _maskMouse.value = pos,
                onPanStart: (pos) {
                  _maskPaths.add(DrawingPath(
                    points: [pos],
                    color: _maskSelectedColor.withValues(alpha: _maskOpacity),
                    strokeWidth: _maskBrushSize,
                  ));
                  _maskRevision.value++;
                  // Once per stroke, for the toolbar's `hasPaths`.
                  setState(() {});
                },
                // Also no setState: a stroke is a drag, so this runs at
                // pointer rate for as long as the button is held.
                onPanUpdate: (pos) {
                  _maskPaths.last.points.add(pos);
                  _maskRevision.value++;
                  _maskMouse.value = pos;
                },
              ),
            ),
          ],
        );
        showRightPanel = false;
        showLeftPanel = false;
        break;
      case 3: // Crop & Resize
        centerContent = const Column(
          children: [
            CropResizeToolbar(),
            Expanded(child: CropResizeView()),
          ],
        );
        showRightPanel = false;
        showLeftPanel = false;
        break;
      case 4: // Prompt Optimizer
        centerContent = Consumer<WorkbenchUIState>(
          builder: (context, wui, _) {
            final session = wui.optimizerSession;
            return ListenableBuilder(
              listenable: session,
              builder: (context, _) {
                // A Selector, not a `Provider.of(context)` up in the enclosing
                // build. Reading the queue there subscribed the *screen* to it,
                // so the 500ms progress tick of any unrelated image or video
                // task rebuilt the whole workbench — top bar, toolbar, chat
                // view and right panel — while this tab was open. The scan
                // still runs per notification; only a flip of the flag now
                // costs a rebuild, and only of this subtree.
                return Selector<TaskQueueService, String?>(
                  // The task's *id*, not merely whether one exists: `10i`'s
                  // 中断 has to name the task it is stopping, and a bool would
                  // have had the abort handler re-scan the queue at the moment
                  // it fires — after the state it was deciding from is gone.
                  selector: (_, queue) => queue.queue
                      .cast<TaskItem?>()
                      .firstWhere(
                        (t) =>
                            t!.type == TaskType.promptRefine &&
                            t.parameters['sessionId'] == session.id &&
                            (t.status == TaskStatus.pending ||
                                t.status == TaskStatus.processing),
                        orElse: () => null,
                      )
                      ?.id,
                  builder: (context, runningTaskId, _) {
                    final isBusy = session.isRunning || runningTaskId != null;
                    return Column(
                      children: [
                        PromptOptimizerToolbar(
                          onNewSession: () => wui.newOptimizerSession(),
                          onHistory: _showAssistantHistory,
                          onApply: () => _handleOptimizerApply(session.refinedPrompt ?? ''),
                          isRefining: isBusy,
                          runningSteps:
                              isBusy ? PromptOptimizerAgent.currentTurnSteps(session) : null,
                          canApply: session.refinedPrompt != null,
                          pendingKbEdits:
                              PromptOptimizerAgent.pendingKbEdits(session).length,
                          onWriteAllKbEdits: isBusy
                              ? null
                              : () => _handleKbEditApplyAll(session),
                          onDiscardAllKbEdits: isBusy
                              ? null
                              : () => _handleKbEditRejectAll(session),
                          modeLabel: switch (session.mode) {
                            AssistantMode.systemPrompt =>
                              AppLocalizations.of(context)!.optModeSystemPrompt,
                            AssistantMode.knowledgeBase =>
                              AppLocalizations.of(context)!.optModeKnowledge,
                            AssistantMode.knowledgeEdit =>
                              AppLocalizations.of(context)!.optModeKnowledgeEdit,
                          },
                          modeIcon: switch (session.mode) {
                            AssistantMode.systemPrompt => Icons.notes_outlined,
                            AssistantMode.knowledgeBase => Icons.menu_book_outlined,
                            AssistantMode.knowledgeEdit => Icons.edit_note_outlined,
                          },
                        ),
                        Expanded(
                          child: _optIsLoadingData
                              ? const Center(child: CircularProgressIndicator())
                              : PromptOptimizerChatView(
                                  inputCtrl: _optInputCtrl,
                                  onSend: _handleOptimizerSend,
                                  onRetry: _handleOptimizerRetry,
                                  onApplyPrompt: _handleOptimizerApply,
                                  onApplyKbEdit: (editId) => _handleKbEditApply(session, editId),
                                  onRejectKbEdit: (editId) => _handleKbEditReject(session, editId),
                                  onAnswerAskUser: _handleAskUserAnswer,
                                  onDistill:
                                      session.usesKnowledgeBase ? _handleKbDistill : null,
                                  onSaveFinalPrompt: _handleSaveFinalPrompt,
                                  isBusy: isBusy,
                                  // Only while there is a task to stop. A
                                  // session whose `isRunning` outlived its
                                  // task — the failure mode a crashed turn
                                  // leaves behind — has nothing to cancel, and
                                  // offering the button there would produce a
                                  // control that does nothing when pressed.
                                  onAbort: runningTaskId == null
                                      ? null
                                      : () => _handleOptimizerAbort(runningTaskId),
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
        // `10h` swaps this column for the knowledge tree in library-edit
        // mode; [OptimizerLeftPanel] owns that choice so the screen still
        // hands the layout one widget rather than rebuilding the decision.
        leftPanel = OptimizerLeftPanel(kbPath: _kbPath);
        showRightPanel = !isNarrow;
        showLeftPanel = !isNarrow; // Show reference images on left
        // The one centre column the spec gives a ground of its own: `10g`
        // draws the chat column `#F5F7FD`, a recess between the `#FAFBFF`
        // panels either side. Every other tab leaves the column bare.
        centerGround = Theme.of(context).colorScheme.surface;
        break;
      case 5: // Video Generation
        centerContent = const Column(
          children: [
            GalleryToolbar(),
            Expanded(
              child: Stack(
                children: [
                  Gallery(),
                  VideoWorkbenchOverlay(),
                ],
              ),
            ),
          ],
        );
        showRightPanel = !isNarrow;
        showLeftPanel = appState.isSidebarExpanded;
        break;
      default:
        centerContent = Center(child: Text(AppLocalizations.of(context)!.comingSoon));
        showRightPanel = false;
        showLeftPanel = false;
    }

    // Context-aware FAB icon for mobile (null = no FAB for that tab)
    final IconData? fabIcon = switch (appState.workbenchTabIndex) {
      0 => Icons.tune,
      1 => Icons.info_outline,
      4 => Icons.auto_awesome_outlined,
      5 => Icons.tune,
      _ => null,
    };

    return WorkbenchLayout(
      topBar: WorkbenchTopBar(tabController: _tabController),
      leftPanel: leftPanel,
      centerContent: centerContent,
      centerGround: centerGround,
      // Const where there is no controller to thread, which is both places the
      // layout draws the panel inline or in its drawer. This builder is
      // re-invoked from `_WorkbenchLayoutState.build` — so on every splitter
      // drag frame, and on every `AppState` notification through the enclosing
      // build — and a freshly allocated widget always forces the child to
      // rebuild, because `Widget` has no `==` and `Element.updateChild` can
      // only skip when the two are identical. A canonicalised const instance
      // is identical, so the panels' own `context.select` calls decide when
      // they rebuild instead of being overruled from above. `leftPanel` above
      // is const for the same reason.
      rightPanelBuilder: (scrollController) {
        switch (appState.workbenchTabIndex) {
          case 0:
            return scrollController == null
                ? const WorkbenchConfigPanel()
                : WorkbenchConfigPanel(scrollController: scrollController);
          case 1:
            return scrollController == null
                ? const MetadataInspector()
                : MetadataInspector(scrollController: scrollController);
          case 4:
            // Two listeners, both needed. The Consumer catches the picker
            // and mode changes: the enclosing build reads WorkbenchUIState
            // with listen: false, so without it nothing rebuilds this panel
            // when a segment is tapped — and a mode switch installs a *new*
            // session object, so the inner builder has to be re-created
            // against it. The ListenableBuilder catches what moves during a
            // turn: the cited files and the context usage.
            return Consumer<WorkbenchUIState>(
              builder: (context, wui, _) => ListenableBuilder(
                listenable: wui.optimizerSession,
                builder: (context, _) => OptimizerConfigPanel(
                  scrollController: scrollController,
                  selectedModelDbId: wui.optSelectedModelDbId,
                  selectedSysPrompt: wui.optSelectedSysPrompt,
                  sysPromptTemplateId: wui.optSysPromptTemplateId,
                  mode: wui.assistantMode,
                  kbStatus: _kbStatus,
                  kbPath: _kbPath,
                  running: _optRunningForSession(wui.optimizerSession),
                  pendingKbEdits: PromptOptimizerAgent.pendingKbEdits(wui.optimizerSession),
                  onWriteAllKbEdits: () => _handleKbEditApplyAll(wui.optimizerSession),
                  onDiscardAllKbEdits: () => _handleKbEditRejectAll(wui.optimizerSession),
                  writePolicy: _kbWritePolicy,
                  onWritePolicyChanged: _handleWritePolicyChanged,
                  onModeChanged: _handleAssistantModeChange,
                  onScaffoldKb: _handleScaffoldKb,
                  sysPrompts: _optSysPrompts,
                  citedKnowledgeFiles: PromptOptimizerAgent.citedKnowledgeFiles(
                    wui.optimizerSession,
                  ),
                  transcript: wui.optimizerSession.transcript,
                  contextUsage: PromptOptimizerAgent.measureContext(
                    wui.optimizerSession,
                    // Read from the picker rather than from the last turn: pick a
                    // different model and the same conversation is measured against
                    // the new window immediately, which is the question the user is
                    // asking when they switch.
                    contextWindowTokens: appState.allModels
                        .cast<LLMModel?>()
                        .firstWhere(
                          (m) => m?.id == wui.optSelectedModelDbId,
                          orElse: () => null,
                        )
                        ?.contextWindow,
                  ),
                  onModelChanged: (v) => wui.setOptimizerModel(v),
                  onSysPromptChanged: (v) => wui.setOptimizerSysPrompt(v),
                  onSysPromptTemplateChanged: (id, content) =>
                      wui.setOptimizerSysPromptTemplate(id, content),
                  onSaveTemplate: _handleSaveSysPromptTemplate,
                ),
              ),
            );
          case 5:
            // Const on the inline path, like cases 0 and 1 — see the note
            // above this builder. A freshly allocated widget is never
            // identical to the last one, so returning one unconditionally
            // forced the whole panel to rebuild on every splitter-drag frame
            // and every AppState notification.
            return scrollController == null
                ? const VideoConfigPanel()
                : VideoConfigPanel(scrollController: scrollController);
          default:
            return const SizedBox.shrink();
        }
      },
      bottomPanel: const AppRunConsole(),
      showLeftPanel: showLeftPanel,
      showRightPanel: showRightPanel,
      fabIcon: fabIcon,
    );
  }
}
