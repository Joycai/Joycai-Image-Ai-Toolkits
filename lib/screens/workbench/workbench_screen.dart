import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_paths.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/task_queue_service.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/drawing_canvas.dart';
import '../../widgets/markdown_editor.dart';
import '../../widgets/unified_sidebar.dart';
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
import 'widgets/optimizer_reference_panel.dart';
import 'widgets/prompt_optimizer_toolbar.dart';
import 'widgets/prompt_optimizer_view.dart';
import 'widgets/video_config_panel.dart';
import 'widgets/video_workbench_view.dart';
import 'widgets/workbench_bottom_console.dart';
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
  String? _activeRefineTaskId;
  Timer? _promptSaveTimer;

  // Mask Editor State
  final List<DrawingPath> _maskPaths = [];
  Color _maskSelectedColor = Colors.white;
  double _maskBrushSize = 20.0;
  double _maskOpacity = 1.0;
  bool _maskIsBinaryMode = false;
  final GlobalKey _maskRepaintKey = GlobalKey();
  Offset? _maskMousePosition;
  
  // Prompt Optimizer State
  late MarkdownTextEditingController _optCurrentPromptCtrl;
  final MarkdownTextEditingController _optRefinedPromptCtrl = MarkdownTextEditingController();
  List<SystemPrompt> _optAllSysPrompts = [];
  List<SystemPrompt> _optFilteredSysPrompts = [];
  List<PromptTag> _optTags = [];
  bool _optIsLoadingData = true;

  @override
  void initState() {
    super.initState();
    // We'll initialize _appState in didChangeDependencies
    _optCurrentPromptCtrl = MarkdownTextEditingController();
    _optCurrentPromptCtrl.addListener(_onOptCurrentPromptChanged);
  }

  void _onOptCurrentPromptChanged() {
    if (_appState != null && _optCurrentPromptCtrl.text != _appState!.lastPrompt) {
      _appState!.lastPrompt = _optCurrentPromptCtrl.text;
      _promptSaveTimer?.cancel();
      _promptSaveTimer = Timer(const Duration(seconds: 1), () {
        _appState!.updateWorkbenchConfig(prompt: _optCurrentPromptCtrl.text);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appState == null) {
      _appState = Provider.of<AppState>(context, listen: false);
      _optCurrentPromptCtrl.text = _appState!.workbenchTabIndex == 5 ? _appState!.lastVideoPrompt : _appState!.lastPrompt;
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
    if (_activeRefineTaskId != null && event.taskId == _activeRefineTaskId) {
      if (event.type == TaskEventType.textChunk) {
        if (mounted) {
          setState(() {
            _optRefinedPromptCtrl.text += (event.data as String);
          });
        }
      }
    }

    if (event.type == TaskEventType.imageResult && event.taskType == TaskType.videoGenerate) {
      if (!mounted) return;
      final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
      uiState.setLastGeneratedVideoPath(event.data as String);
    }
  }

  void _onWorkbenchUIChanged() {
    if (!mounted) return;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    
    // If we have a fresh manual data transfer
    if (workbenchUIState.optimizerRoughPrompt.isNotEmpty) {
      setState(() {
        _optCurrentPromptCtrl.text = workbenchUIState.optimizerRoughPrompt;
        // The images are used by the sidebar reference panel via Provider
      });
      // Reset the trigger in UI State to prevent overwriting on subsequent refreshes
      workbenchUIState.clearOptimizerTransfer();
    }
  }

  // Optimizer Helpers
  Future<void> _loadOptimizerData() async {
    if (_appState == null) return;
    try {
      final refinerPrompts = await _appState!.getSystemPrompts(type: 'refiner');
      final tags = await _appState!.getPromptTags();

      if (mounted) {
        final wuiState = Provider.of<WorkbenchUIState>(context, listen: false);
        setState(() {
          _optAllSysPrompts = refinerPrompts;
          _optTags = tags;
          _applyOptimizerFilter(wuiState);

          // Only set defaults on first load; preserve user's previous selections.
          if (wuiState.optSelectedModelDbId == null && _appState!.chatModels.isNotEmpty) {
            wuiState.setOptimizerModel(_appState!.chatModels.first.id);
          }
          if (wuiState.optSelectedSysPrompt == null && _optFilteredSysPrompts.isNotEmpty) {
            wuiState.setOptimizerSysPrompt(_optFilteredSysPrompts.first.content);
          }
          _optIsLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _optIsLoadingData = false);
    }
  }

  void _applyOptimizerFilter(WorkbenchUIState wuiState) {
    if (wuiState.optSelectedTagId == null) {
      _optFilteredSysPrompts = _optAllSysPrompts;
    } else {
      _optFilteredSysPrompts = _optAllSysPrompts.where((p) => p.tags.any((t) => t.id == wuiState.optSelectedTagId)).toList();
    }
    if (wuiState.optSelectedSysPrompt != null && !_optFilteredSysPrompts.any((p) => p.content == wuiState.optSelectedSysPrompt)) {
      wuiState.setOptimizerSysPrompt(_optFilteredSysPrompts.isNotEmpty ? _optFilteredSysPrompts.first.content : null);
    }
  }

  Future<void> _handleRefine() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    
    if (workbenchUIState.optSelectedModelDbId == null || _appState == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noModelsConfigured)));
      return;
    }

    try {
      final taskService = Provider.of<TaskQueueService>(context, listen: false);
      final taskId = const Uuid().v4();

      setState(() {
        _activeRefineTaskId = taskId;
        _optRefinedPromptCtrl.clear();
      });

      await taskService.addTask(
        workbenchUIState.optimizerReferenceImages.map((f) => f.path).toList(),
        workbenchUIState.optSelectedModelDbId!,
        {
          'systemPrompt': workbenchUIState.optSelectedSysPrompt,
          'roughPrompt': _optCurrentPromptCtrl.text,
        },
        type: TaskType.promptRefine,
        useStream: true,
        id: taskId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.taskSubmitted),
          backgroundColor: Colors.blue,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refineFailed(e.toString()))));
    }
  }

  void _handleOptimizerApply() {
    if (_appState == null) return;
    _appState!.updateWorkbenchConfig(prompt: _optRefinedPromptCtrl.text);
    _appState!.setWorkbenchTab(0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.promptApplied)));
  }

  void _onAppStateChanged() {
    if (!mounted || _appState == null) return;
    
    if (_appState!.workbenchTabIndex != _lastKnownTabIndex) {
      _lastKnownTabIndex = _appState!.workbenchTabIndex;
      final targetIndex = _lastKnownTabIndex.clamp(0, _tabController.length - 1);
      if (_tabController.index != targetIndex) {
         _tabController.animateTo(targetIndex);
      }
      
      // Update optimizer prompt if switching to/from video tab
      if (_tabController.index == 4) {
        final currentWorkspacePrompt = _appState!.workbenchTabIndex == 5 ? _appState!.lastVideoPrompt : _appState!.lastPrompt;
        if (_optCurrentPromptCtrl.text != currentWorkspacePrompt) {
          setState(() {
            _optCurrentPromptCtrl.text = currentWorkspacePrompt;
          });
        }
      }
    }
  }

  // Mask Editor Helpers
  void _handleMaskUndo() => setState(() { if (_maskPaths.isNotEmpty) _maskPaths.removeLast(); });
  void _handleMaskClear() => setState(() => _maskPaths.clear());
  
  Future<void> _handleMaskSave({bool binary = false, bool selectAfterSave = true}) async {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final sourceImage = workbenchUIState.maskEditorSourceImage;
    if (sourceImage == null || _appState == null) return;

    final originalBinaryMode = _maskIsBinaryMode;
    if (binary != _maskIsBinaryMode) {
      setState(() => _maskIsBinaryMode = binary);
      // Wait for the next frame to ensure the UI has updated to show/hide the image
      await Future.delayed(const Duration(milliseconds: 50));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.maskSaved), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.maskSaveError(e.toString())), backgroundColor: Colors.red),
        );
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
    _promptSaveTimer?.cancel();
    _optCurrentPromptCtrl.removeListener(_onOptCurrentPromptChanged);
    _optCurrentPromptCtrl.dispose();
    _optRefinedPromptCtrl.dispose();
    _appState?.removeListener(_onAppStateChanged);
    _workbenchUIState?.removeListener(_onWorkbenchUIChanged);
    _taskSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final isNarrow = Responsive.isNarrow(context);

    // Determine content based on active tab
    Widget centerContent;
    Widget leftPanel = const UnifiedSidebar();
    bool showLeftPanel = appState.isSidebarExpanded;
    bool showRightPanel = !isNarrow;

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
        showRightPanel = !isNarrow; // Show metadata on right
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
                selectedColor: _maskSelectedColor.withValues(alpha: _maskOpacity),
                brushSize: _maskBrushSize,
                isBinaryMode: _maskIsBinaryMode,
                repaintKey: _maskRepaintKey,
                mousePosition: _maskMousePosition,
                onHover: (pos) => setState(() => _maskMousePosition = pos),
                onPanStart: (pos) => setState(() {
                  _maskPaths.add(DrawingPath(
                    points: [pos], 
                    color: _maskSelectedColor.withValues(alpha: _maskOpacity), 
                    strokeWidth: _maskBrushSize
                  ));
                }),
                onPanUpdate: (pos) => setState(() {
                  _maskPaths.last.points.add(pos);
                  _maskMousePosition = pos;
                }),
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
        final taskService = Provider.of<TaskQueueService>(context);
        final isRefining = taskService.queue.any((t) => t.type == TaskType.promptRefine && t.status == TaskStatus.processing);

        centerContent = Column(
          children: [
            PromptOptimizerToolbar(
              onRefine: _handleRefine,
              onApply: _handleOptimizerApply,
              onClear: () => setState(() { _optCurrentPromptCtrl.clear(); _optRefinedPromptCtrl.clear(); }),
              isRefining: isRefining,
              canRefine: workbenchUIState.optSelectedSysPrompt != null,
              canApply: _optRefinedPromptCtrl.text.isNotEmpty,
            ),
            Expanded(
              child: _optIsLoadingData 
                ? const Center(child: CircularProgressIndicator())
                : PromptOptimizerView(
                    currentPromptCtrl: _optCurrentPromptCtrl,
                    refinedPromptCtrl: _optRefinedPromptCtrl,
                  ),
            ),
          ],
        );
        leftPanel = const OptimizerReferencePanel();
        showRightPanel = !isNarrow;
        showLeftPanel = !isNarrow; // Show reference images on left
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
      rightPanelBuilder: (scrollController) {
        switch (appState.workbenchTabIndex) {
          case 0:
            return WorkbenchConfigPanel(scrollController: scrollController);
          case 1:
            return MetadataInspector(scrollController: scrollController);
          case 4:
            return OptimizerConfigPanel(
              scrollController: scrollController,
              selectedModelDbId: workbenchUIState.optSelectedModelDbId,
              selectedTagId: workbenchUIState.optSelectedTagId,
              selectedSysPrompt: workbenchUIState.optSelectedSysPrompt,
              tags: _optTags,
              filteredSysPrompts: _optFilteredSysPrompts,
              onModelChanged: (v) => workbenchUIState.setOptimizerModel(v),
              onTagChanged: (v) {
                workbenchUIState.setOptimizerTag(v);
                setState(() => _applyOptimizerFilter(workbenchUIState));
              },
              onSysPromptChanged: (v) => workbenchUIState.setOptimizerSysPrompt(v),
            );
          case 5:
            return VideoConfigPanel(scrollController: scrollController);
          default:
            return const SizedBox.shrink();
        }
      },
      bottomPanel: const WorkbenchBottomConsole(),
      showLeftPanel: showLeftPanel,
      showRightPanel: showRightPanel,
      fabIcon: fabIcon,
    );
  }
}
