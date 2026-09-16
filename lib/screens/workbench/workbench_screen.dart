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
import '../../core/design_tokens.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/llm_model.dart';
import '../../models/prompt.dart';
import '../../services/assistant/assistant_kb_distill.dart';
import '../../services/assistant/knowledge_base_service.dart';
import '../../services/assistant/knowledge_base_starter.dart';
import '../../services/assistant/prompt_optimizer_agent.dart';
import '../../services/assistant/prompt_provenance.dart';
import '../../services/tasks/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_dialog.dart';
import '../../widgets/ui/app_field_size.dart';
import '../../widgets/tasks/app_run_console.dart';
import '../../widgets/ui/app_snackbar.dart';
import '../../widgets/ui/listenable_selector.dart';
import '../../widgets/models/model_edit_dialog.dart';
import 'widgets/drawing_canvas.dart';
import '../batch/task_queue_screen.dart';
import 'unified_sidebar.dart';
import '../prompts/widgets/prompt_dialogs.dart';
import 'gallery.dart';
import 'widgets/gallery_selection_bar.dart';
import 'widgets/video_gallery_area.dart';
import 'widgets/workbench_glass_toolbar.dart';
import 'widgets/comparator_toolbar.dart';
import 'widgets/comparator_view.dart';
import 'widgets/crop_resize_toolbar.dart';
import 'widgets/crop_resize_view.dart';
import 'widgets/mask_editor_toolbar.dart';
import 'widgets/mask_editor_view.dart';
import 'widgets/metadata_inspector.dart';
import 'widgets/optimizer_config_panel.dart';
import 'widgets/optimizer_left_panel.dart';
import 'widgets/prompt_optimizer_toolbar.dart';
import 'widgets/prompt_optimizer_view.dart';
import 'widgets/video_config_panel.dart';
import 'workbench_config_panel.dart';
import 'workbench_layout.dart';

part 'workbench_assistant/assistant_actions.dart';
part 'workbench_assistant/assistant_history_sheet.dart';
part 'workbench_assistant/assistant_tab.dart';
part 'workbench_assistant/assistant_turns.dart';

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
      final RenderRepaintBoundary? boundary = _maskRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      
      // Get image dimensions to maintain resolution
      final bytes = await File(sourceImage.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      final double pixelRatio = img.width / boundary.size.width;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
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

    // A tool tab's own controls, which live in the floating toolbar.
    Widget? toolControls;
    double toolControlsWidth = 0;

    switch (appState.workbenchTabIndex) {
      case 0: // Image Processing
        // The gallery scrolls under the floating toolbar and above the
        // selection bar (`A1 · 1a`), so it takes the whole column.
        centerContent = const Gallery();
        showRightPanel = !isNarrow; // Only show on desktop by default
      case 1: // Comparator
        // `A5`: the tool's controls sit in the glass bar's slot, so the images
        // take the whole column below it.
        centerContent = const ComparatorView();
        toolControls = const ComparatorToolbar();
        toolControlsWidth = ComparatorToolbar.preferredWidth(context);
        // The toolbar's metadata button switches this on desktop; on narrow
        // the panel is a drawer the same button opens instead.
        showRightPanel = !isNarrow && context.watch<WorkbenchUIState>().comparatorShowMetadata;
        showLeftPanel = false; // Auto-hide sidebar
      case 2: // Mask Editor
        // `A6`: the brush, the colours and the saves sit in the glass bar's
        // slot, so the canvas takes the whole column below it.
        toolControls = MaskEditorToolbar(
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
        );
        toolControlsWidth = MaskEditorToolbar.preferredWidth(context);
        centerContent = MaskEditorView(
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
        );
        showRightPanel = false;
        showLeftPanel = false;
      case 3: // Crop & Resize
        // `A4`: the tool's controls sit in the glass bar's slot, so the canvas
        // takes the whole column below it.
        centerContent = const CropResizeView();
        toolControls = const CropResizeToolbar();
        toolControlsWidth = CropResizeToolbar.preferredWidth(context);
        showRightPanel = false;
        showLeftPanel = false;
      case 4: // Prompt Optimizer
        centerContent = _buildAssistantChat();
        // `10h` swaps this column for the knowledge tree in library-edit
        // mode; [OptimizerLeftPanel] owns that choice so the screen still
        // hands the layout one widget rather than rebuilding the decision.
        // The assistant's header lives in the floating glass toolbar
        // (`A3a 1a`), fed by the same session and queue the chat reads.
        toolControls = _buildAssistantToolControls();
        {
          final wuiNow = context.read<WorkbenchUIState>();
          final l10nNow = AppLocalizations.of(context)!;
          toolControlsWidth = PromptOptimizerToolbar.preferredWidth(
            context,
            modeLabel: switch (wuiNow.assistantMode) {
              AssistantMode.systemPrompt => l10nNow.optModeSystemPrompt,
              AssistantMode.knowledgeBase => l10nNow.optModeKnowledge,
              AssistantMode.knowledgeEdit => l10nNow.optModeKnowledgeEdit,
            },
            pendingKbEdits: PromptOptimizerAgent.pendingKbEdits(wuiNow.optimizerSession).length,
          );
        }
        leftPanel = OptimizerLeftPanel(kbPath: _kbPath);
        showRightPanel = !isNarrow;
        // Reference images on the left, behind the toolbar's sidebar toggle
        // like the gallery's folders.
        showLeftPanel = appState.isSidebarExpanded;
        // The one centre column the spec gives a ground of its own: `10g`
        // draws the chat column `#F5F7FD`, a recess between the `#FAFBFF`
        // panels either side. Every other tab leaves the column bare.
        centerGround = Theme.of(context).colorScheme.surface;
      case 5: // Video Generation
        // The gallery with the last result's player over its bottom edge,
        // padded so the grid's last row clears it (`A2 · 1a`).
        centerContent = const VideoGalleryArea();
        showRightPanel = !isNarrow;
        showLeftPanel = appState.isSidebarExpanded;
      default:
        centerContent = Center(child: Text(AppLocalizations.of(context)!.comingSoon));
        showRightPanel = false;
        showLeftPanel = false;
    }

    final tab = appState.workbenchTabIndex;
    final isGalleryTab = WorkbenchTab.isGallery(tab);
    // `A1` spec: on a phone the FAB gives way to the selection bar.
    //
    // Read behind the width check, and `&&` short-circuits, so on a desktop
    // window the dependency is never registered. It used to be: a screen that
    // does not draw a FAB at all rebuilt itself entirely — both panels, the
    // toolbar, the config panel and every visible card — whenever a selection
    // crossed between empty and not. `isNarrow` rather than `isMobile`
    // because WorkbenchLayout switches to the phone form on *content* width,
    // which trails the window by the width of the rail.
    final hasSelection = isNarrow &&
        context.select<GalleryState, bool>((g) => g.selectedImages.isNotEmpty);

    // Context-aware FAB icon for mobile (null = no FAB for that tab)
    final IconData? fabIcon = switch (tab) {
      WorkbenchTab.image || WorkbenchTab.video => hasSelection ? null : Icons.tune,
      WorkbenchTab.comparator => Icons.info_outline,
      WorkbenchTab.assistant => Icons.auto_awesome_outlined,
      _ => null,
    };

    final l10n = AppLocalizations.of(context)!;

    return WorkbenchLayout(
      toolbarBuilder: (phone) => WorkbenchGlassToolbar(
        tabController: _tabController,
        phone: phone,
        toolControls: toolControls,
        toolControlsWidth: toolControlsWidth,
      ),
      centerOverlay: tab == WorkbenchTab.video
          ? const VideoTabSelectionBar()
          : (isGalleryTab ? const GallerySelectionBar() : null),
      centerScrollsUnderToolbar: isGalleryTab,
      hasLeftPanel: tab == WorkbenchTab.image || tab == WorkbenchTab.video || tab == WorkbenchTab.assistant,
      hasRightPanel: tab != WorkbenchTab.mask && tab != WorkbenchTab.crop,
      rightPanelTitle: isGalleryTab ? l10n.wbGenerationConfig : null,
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
            return _buildAssistantConfigPanel(scrollController, appState);
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
      bottomPanel: const AppRunConsole(onExpand: showTaskQueueSheet),
      showLeftPanel: showLeftPanel,
      showRightPanel: showRightPanel,
      fabIcon: fabIcon,
    );
  }
}
