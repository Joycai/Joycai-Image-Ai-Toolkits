import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/app_paths.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_file.dart';
import '../../../services/llm/llm_models.dart';
import '../../../services/llm/llm_service.dart';
import '../../../state/app_state.dart';
import '../../../state/window_state.dart';
import '../../../widgets/drawing_canvas.dart';

class MaskEditorSidebarView extends StatefulWidget {
  const MaskEditorSidebarView({super.key});

  @override
  State<MaskEditorSidebarView> createState() => _MaskEditorSidebarViewState();
}

class _MaskEditorSidebarViewState extends State<MaskEditorSidebarView> {
  final GlobalKey _repaintKey = GlobalKey();
  List<DrawingPath> _paths = [];
  Color _selectedColor = Colors.white;
  double _brushSize = 20.0;
  
  ui.Image? _imageInfo;
  bool _isLoading = true;
  Offset? _mousePosition;
  bool _isBinaryMode = false;
  
  // AI Mask State
  bool _showAIPanel = false;
  final TextEditingController _aiPromptController = TextEditingController();
  bool _isGeneratingMask = false;
  String? _selectedModelId;
  double _pointCount = 200.0;
  
  AppFile? _lastSourceImage;

  @override
  void initState() {
    super.initState();
    _initModel();
  }
  
  void _initModel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.imageModels.isNotEmpty && _selectedModelId == null) {
        setState(() {
          _selectedModelId = appState.imageModels.first.modelId;
        });
      }
    });
  }

  @override
  void dispose() {
    _aiPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadImage(AppFile sourceImage) async {
    setState(() {
      _isLoading = true;
      _paths = [];
      _lastSourceImage = sourceImage;
    });
    
    try {
      final bytes = await File(sourceImage.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _imageInfo = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _undo() {
    if (_paths.isNotEmpty) {
      setState(() {
        _paths.removeLast();
      });
    }
  }

  void _clear() {
    setState(() {
      _paths = [];
    });
  }

  Future<void> _generateAIMask(AppFile sourceImage) async {
    final prompt = _aiPromptController.text.trim();
    if (prompt.isEmpty) return;
    
    final l10n = AppLocalizations.of(context)!;

    if (_selectedModelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.noModelsConfigured),
          action: SnackBarAction(
            label: l10n.settings,
            onPressed: () {
              // Note: Sidebar will remain open, but we navigate to settings in main view?
              // Or close sidebar? For now, let's close sidebar to show settings.
              final appState = Provider.of<AppState>(context, listen: false);
              appState.setSidebarExpanded(false); // Close sidebar
              appState.navigateToScreen(6); // Settings
            },
          ),
        ),
      );
      return;
    }

    setState(() => _isGeneratingMask = true);

    try {
      final imageBytes = await File(sourceImage.path).readAsBytes();
      final mimeType = p.extension(sourceImage.path).toLowerCase().replaceAll('.', 'image/');

      final systemPrompt = """
You are an AI assistant that identifies objects in images.
Return a list of [x, y] coordinates (0-1000 scale) that outline the object described by the user.
Format: JSON { "points": [[x1, y1], [x2, y2], ...] }
Keep the number of points around ${_pointCount.toInt()} for a detailed polygon mask.
Ensure the coordinates form a closed loop (last point connects to first).
Do NOT output markdown. Output ONLY raw JSON.
""";

      final userMessage = LLMMessage(
        role: LLMRole.user,
        content: "Outline this object: $prompt",
        attachments: [
          LLMAttachment.fromBytes(imageBytes, mimeType == 'image/jpg' ? 'image/jpeg' : mimeType),
        ],
      );

      final response = await LLMService().request(
        modelIdentifier: _selectedModelId,
        messages: [
          LLMMessage(role: LLMRole.system, content: systemPrompt),
          userMessage,
        ],
        useStream: false,
      );

      final jsonStr = response.text.replaceAll('```json', '').replaceAll('```', '').trim();
      final data = jsonDecode(jsonStr);
      final List pointsData = data['points'];

      if (pointsData.isNotEmpty && _repaintKey.currentContext != null) {
        final RenderBox renderBox = _repaintKey.currentContext!.findRenderObject() as RenderBox;
        final double width = renderBox.size.width;
        final double height = renderBox.size.height;

        final List<Offset> points = pointsData.map((pt) {
          final x = (pt[0] as num) / 1000 * width;
          final y = (pt[1] as num) / 1000 * height;
          return Offset(x, y);
        }).toList();

        // Close the loop
        if (points.first != points.last) {
          points.add(points.first);
        }

        setState(() {
          _paths.add(DrawingPath(
            points: points,
            color: _selectedColor,
            strokeWidth: _brushSize,
            isPolygon: true,
          ));
          _showAIPanel = false;
        });
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI Mask generated successfully'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI Generation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingMask = false);
    }
  }

  Future<Uint8List?> _captureMask() async {
    try {
      RenderRepaintBoundary boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      double pixelRatio = _imageInfo!.width / boundary.size.width;
      
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveMask(AppFile sourceImage) async {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    
    try {
      final pngBytes = await _captureMask();
      if (pngBytes == null) throw Exception("Failed to capture mask");

      final tempDir = await AppPaths.getTempDirectory();
      final maskDir = Directory(p.join(tempDir, 'joycai', 'masks'));
      if (!maskDir.existsSync()) {
        maskDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'mask_${p.basenameWithoutExtension(sourceImage.path)}_$timestamp.png';
      final filePath = p.join(maskDir.path, fileName);
      
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      final maskFile = AppFile(path: filePath, name: fileName);
      appState.galleryState.addDroppedFiles([maskFile]);
      appState.galleryState.toggleImageSelection(maskFile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.renameSuccess), backgroundColor: Colors.green),
        );
        // Switch to directories or gallery to show the result
        appState.setSidebarMode(SidebarMode.directories);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final windowState = Provider.of<WindowState>(context);
    final sourceImage = windowState.maskEditorSourceImage;

    if (sourceImage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.brush, size: 48, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              "No image selected for masking",
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_lastSourceImage?.path != sourceImage.path) {
      _loadImage(sourceImage);
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          color: colorScheme.surfaceContainerHighest,
          child: Column(
            children: [
              Row(
                children: [
                  Tooltip(
                    message: "AI Smart Mask",
                    child: IconButton(
                      icon: Icon(Icons.auto_awesome, size: 20, color: _showAIPanel ? colorScheme.primary : colorScheme.onSurface),
                      onPressed: () => setState(() => _showAIPanel = !_showAIPanel),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(_isBinaryMode ? Icons.contrast : Icons.image, size: 20),
                    onPressed: () => setState(() => _isBinaryMode = !_isBinaryMode),
                    tooltip: "Binary Mask Mode",
                  ),
                  IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: _paths.isEmpty ? null : _undo,
                    tooltip: l10n.undo,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: _paths.isEmpty ? null : _clear,
                    tooltip: l10n.clear,
                  ),
                ],
              ),
              const Divider(height: 8),
              Row(
                children: [
                   _buildColorCircle(Colors.black, l10n.black),
                   _buildColorCircle(Colors.white, l10n.white),
                   if (!_isBinaryMode) ...[
                      _buildColorCircle(Colors.red, l10n.red),
                      _buildColorCircle(Colors.green, l10n.green),
                   ],
                   const Expanded(child: SizedBox()),
                   SizedBox(
                     width: 100,
                     child: Slider(
                       value: _brushSize,
                       min: 1,
                       max: 100,
                       onChanged: (v) => setState(() => _brushSize = v),
                     ),
                   ),
                ],
              ),
              const Divider(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _saveMask(sourceImage),
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(l10n.saveAndSelect, style: const TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Drawing Area
        Expanded(
          child: Container(
            color: Colors.black,
            child: InteractiveViewer(
              maxScale: 10.0,
              minScale: 0.1,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _imageInfo!.width / _imageInfo!.height,
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_isBinaryMode)
                          Container(color: Colors.black)
                        else
                          Image.file(File(sourceImage.path), fit: BoxFit.fill),
                        
                        MouseRegion(
                          cursor: SystemMouseCursors.none,
                          onHover: (event) => setState(() => _mousePosition = event.localPosition),
                          onExit: (event) => setState(() => _mousePosition = null),
                          child: GestureDetector(
                            onPanStart: (details) {
                              setState(() {
                                _paths.add(DrawingPath(
                                  points: [details.localPosition],
                                  color: _selectedColor,
                                  strokeWidth: _brushSize,
                                ));
                              });
                            },
                            onPanUpdate: (details) {
                              setState(() {
                                _paths.last.points.add(details.localPosition);
                                _mousePosition = details.localPosition;
                              });
                            },
                            child: CustomPaint(
                              painter: MaskPainter(paths: _paths),
                              foregroundPainter: _mousePosition != null 
                                ? BrushPreviewPainter(
                                    position: _mousePosition!, 
                                    size: _brushSize,
                                    color: _selectedColor,
                                  ) 
                                : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // AI Panel Overlay
        if (_showAIPanel)
          Container(
            padding: const EdgeInsets.all(12),
            color: colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("AI Smart Mask", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: colorScheme.primary)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedModelId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select Model',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  items: Provider.of<AppState>(context, listen: false).imageModels.map((m) => DropdownMenuItem(
                    value: m.modelId,
                    child: Text(m.modelName.isNotEmpty ? m.modelName : m.modelId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedModelId = val);
                  },
                ),
                const SizedBox(height: 8),
                Text("Detail: ${_pointCount.toInt()}", style: const TextStyle(fontSize: 10)),
                SizedBox(
                  height: 30,
                  child: Slider(
                    value: _pointCount,
                    min: 10,
                    max: 500,
                    divisions: 49,
                    onChanged: (v) => setState(() => _pointCount = v),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _aiPromptController,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: "Describe what to mask...",
                  ),
                  onSubmitted: (_) => _generateAIMask(sourceImage),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isGeneratingMask ? null : () => _generateAIMask(sourceImage),
                    icon: _isGeneratingMask 
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome, size: 14),
                    label: Text(_isGeneratingMask ? "Generating..." : "Generate", style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildColorCircle(Color color, String tooltip) {
    bool isSelected = _selectedColor == color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: () => setState(() => _selectedColor = color),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
