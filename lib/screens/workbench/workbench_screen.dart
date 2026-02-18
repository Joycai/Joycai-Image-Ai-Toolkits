import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_paths.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_image.dart';
import '../../models/prompt.dart';
import '../../models/tag.dart';
import '../../services/llm/llm_types.dart';
import '../../services/llm/llm_service.dart';
import '../../state/app_state.dart';
import '../../state/gallery_state.dart';
import '../../state/workbench_ui_state.dart';
import '../../widgets/drawing_canvas.dart';
import '../../widgets/unified_sidebar.dart';
import 'widgets/comparator_toolbar.dart';
import 'widgets/mask_editor_toolbar.dart';
import 'widgets/prompt_optimizer_toolbar.dart';
import 'workbench_config_panel.dart';
import 'gallery.dart';
import 'widgets/comparator_view.dart';
import 'widgets/mask_editor_view.dart';
import 'widgets/prompt_optimizer_view.dart';
import 'widgets/gallery_toolbar.dart';
import 'widgets/mask_editor_ai_panel.dart';
import 'widgets/metadata_inspector.dart';
import 'widgets/optimizer_config_panel.dart';
import 'widgets/optimizer_reference_panel.dart';
import 'widgets/workbench_bottom_console.dart';
import 'widgets/workbench_top_bar.dart';
import 'workbench_layout.dart';

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AppState? _appState;
  int _lastKnownTabIndex = 0;

  // Mask Editor State
  final List<DrawingPath> _maskPaths = [];
  Color _maskSelectedColor = Colors.white;
  double _maskBrushSize = 20.0;
  double _maskOpacity = 1.0;
  bool _maskIsBinaryMode = false;
  bool _maskShowAIPanel = false;
  final GlobalKey _maskRepaintKey = GlobalKey();
  Offset? _maskMousePosition;
  
  // AI Mask State
  final TextEditingController _maskAiPromptController = TextEditingController();
  bool _maskIsGeneratingAI = false;
  String? _maskSelectedModelId;
  double _maskPointCount = 200.0;

  // Prompt Optimizer State
  late TextEditingController _optCurrentPromptCtrl;
  final TextEditingController _optRefinedPromptCtrl = TextEditingController();
  List<SystemPrompt> _optAllSysPrompts = [];
  List<SystemPrompt> _optFilteredSysPrompts = [];
  List<PromptTag> _optTags = [];
  int? _optSelectedModelDbId;
  int? _optSelectedTagId;
  String? _optSelectedSysPrompt;
  bool _optIsRefining = false;
  bool _optIsLoadingData = true;

  @override
  void initState() {
    super.initState();
    // We'll initialize _appState in didChangeDependencies
    _optCurrentPromptCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appState == null) {
      _appState = Provider.of<AppState>(context, listen: false);
      _optCurrentPromptCtrl.text = _appState!.lastPrompt;
      _initTabController();
      
      _appState!.addListener(_onAppStateChanged);
      
      // Listen for manual data send from UI State
      final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
      workbenchUIState.addListener(_onWorkbenchUIChanged);
      
      if (_appState!.imageModels.isNotEmpty) {
        _maskSelectedModelId = _appState!.imageModels.first.modelId;
      }
      
      _loadOptimizerData();
    }
  }

  void _onWorkbenchUIChanged() {
    if (!mounted) return;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    
    // If we have a fresh manual data transfer
    if (workbenchUIState.optimizerRoughPrompt.isNotEmpty || workbenchUIState.optimizerReferenceImages.isNotEmpty) {
      setState(() {
        _optCurrentPromptCtrl.text = workbenchUIState.optimizerRoughPrompt;
        // The images are used by the sidebar reference panel via Provider
      });
      // Optionally reset the trigger in UI State if needed, 
      // but keeping it as is allows the optimizer to hold the "last sent" data.
    }
  }

  // Optimizer Helpers
  Future<void> _loadOptimizerData() async {
    if (_appState == null) return;
    try {
      final refinerPrompts = await _appState!.getSystemPrompts(type: 'refiner');
      final tags = await _appState!.getPromptTags();

      if (mounted) {
        setState(() {
          _optAllSysPrompts = refinerPrompts;
          _optTags = tags;
          _applyOptimizerFilter();
          
          if (_appState!.chatModels.isNotEmpty) {
            _optSelectedModelDbId = _appState!.chatModels.first.id;
          }
          if (_optFilteredSysPrompts.isNotEmpty) _optSelectedSysPrompt = _optFilteredSysPrompts.first.content;
          _optIsLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _optIsLoadingData = false);
    }
  }

  void _applyOptimizerFilter() {
    if (_optSelectedTagId == null) {
      _optFilteredSysPrompts = _optAllSysPrompts;
    } else {
      _optFilteredSysPrompts = _optAllSysPrompts.where((p) => p.tags.any((t) => t.id == _optSelectedTagId)).toList();
    }
    if (_optSelectedSysPrompt != null && !_optFilteredSysPrompts.any((p) => p.content == _optSelectedSysPrompt)) {
      _optSelectedSysPrompt = _optFilteredSysPrompts.isNotEmpty ? _optFilteredSysPrompts.first.content : null;
    }
  }

  Future<void> _handleRefine() async {
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    
    if (_optSelectedModelDbId == null || _appState == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noModelsConfigured)));
      return;
    }

    setState(() {
      _optIsRefining = true;
      _optRefinedPromptCtrl.clear();
    });

    try {
      final attachments = workbenchUIState.optimizerReferenceImages.map((f) => 
        LLMAttachment.fromFile(File(f.path), 'image/jpeg')
      ).toList();

      final response = await LLMService().request(
        modelIdentifier: _optSelectedModelDbId!,
        useStream: false,
        messages: [
          if (_optSelectedSysPrompt != null)
            LLMMessage(role: LLMRole.system, content: _optSelectedSysPrompt!),
          LLMMessage(role: LLMRole.user, content: _optCurrentPromptCtrl.text, attachments: attachments),
        ],
      );

      if (mounted) setState(() => _optRefinedPromptCtrl.text = response.text);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.refineFailed(e.toString()))));
    } finally {
      if (mounted) setState(() => _optIsRefining = false);
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

  Future<void> _generateAIMask() async {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    final sourceImage = workbenchUIState.maskEditorSourceImage;
    if (sourceImage == null || _maskAiPromptController.text.trim().isEmpty) return;

    setState(() => _maskIsGeneratingAI = true);

    try {
      final imageBytes = await File(sourceImage.path).readAsBytes();
      final mimeType = p.extension(sourceImage.path).toLowerCase().replaceAll('.', 'image/');

      final systemPrompt = """
Outline the object described by the user.
Return JSON { "points": [[x1, y1], [x2, y2], ...] }
Coordinates are 0-1000. Form a closed loop.
""";

      final response = await LLMService().request(
        modelIdentifier: _maskSelectedModelId,
        messages: [
          LLMMessage(role: LLMRole.system, content: systemPrompt),
          LLMMessage(role: LLMRole.user, content: _maskAiPromptController.text.trim(), attachments: [
            LLMAttachment.fromBytes(imageBytes, mimeType == 'image/jpg' ? 'image/jpeg' : mimeType),
          ]),
        ],
        useStream: false,
      );

      final jsonStr = response.text.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(jsonStr);
      final List pointsData = data['points'];

      if (pointsData.isNotEmpty) {
        final RenderBox renderBox = _maskRepaintKey.currentContext!.findRenderObject() as RenderBox;
        final double width = renderBox.size.width;
        final double height = renderBox.size.height;

        final List<Offset> points = pointsData.map((pt) {
          return Offset((pt[0] as num) / 1000 * width, (pt[1] as num) / 1000 * height);
        }).toList();
        if (points.first != points.last) points.add(points.first);

        setState(() {
          _maskPaths.add(DrawingPath(
            points: points,
            color: _maskSelectedColor.withValues(alpha: _maskOpacity),
            strokeWidth: _maskBrushSize,
            isPolygon: true,
          ));
          _maskShowAIPanel = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.maskGenError(e.toString())), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _maskIsGeneratingAI = false);
    }
  }

  void _initTabController() {
    if (_appState == null) return;
    _lastKnownTabIndex = _appState!.workbenchTabIndex.clamp(0, 3);
    
    _tabController = TabController(length: 4, vsync: this, initialIndex: _lastKnownTabIndex);
    
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
    _appState?.removeListener(_onAppStateChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController.length != 4) {
       _tabController.dispose();
       _initTabController();
    }

    final appState = Provider.of<AppState>(context);
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
              onToggleAI: () => setState(() => _maskShowAIPanel = !_maskShowAIPanel),
              selectedColor: _maskSelectedColor,
              brushSize: _maskBrushSize,
              opacity: _maskOpacity,
              isBinaryMode: _maskIsBinaryMode,
              showAIPanel: _maskShowAIPanel,
              hasPaths: _maskPaths.isNotEmpty,
            ),
            if (_maskShowAIPanel)
              MaskEditorAIPanel(
                selectedModelId: _maskSelectedModelId,
                pointCount: _maskPointCount,
                promptController: _maskAiPromptController,
                isGenerating: _maskIsGeneratingAI,
                onModelChanged: (val) => setState(() => _maskSelectedModelId = val),
                onPointCountChanged: (val) => setState(() => _maskPointCount = val),
                onGenerate: _generateAIMask,
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
      case 3: // Prompt Optimizer
        centerContent = Column(
          children: [
            PromptOptimizerToolbar(
              onRefine: _handleRefine,
              onApply: _handleOptimizerApply,
              onClear: () => setState(() { _optCurrentPromptCtrl.clear(); _optRefinedPromptCtrl.clear(); }),
              isRefining: _optIsRefining,
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
      default:
        centerContent = Center(child: Text(AppLocalizations.of(context)!.comingSoon));
        showRightPanel = false;
        showLeftPanel = false;
    }

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
          case 3:
            return OptimizerConfigPanel(
              scrollController: scrollController,
              selectedModelDbId: _optSelectedModelDbId,
              selectedTagId: _optSelectedTagId,
              selectedSysPrompt: _optSelectedSysPrompt,
              tags: _optTags,
              filteredSysPrompts: _optFilteredSysPrompts,
              onModelChanged: (v) => setState(() => _optSelectedModelDbId = v),
              onTagChanged: (v) => setState(() { _optSelectedTagId = v; _applyOptimizerFilter(); }),
              onSysPromptChanged: (v) => setState(() => _optSelectedSysPrompt = v),
            );
          default:
            return const SizedBox.shrink();
        }
      },
      bottomPanel: const WorkbenchBottomConsole(),
      showLeftPanel: showLeftPanel,
      showRightPanel: showRightPanel,
    );
  }
}
