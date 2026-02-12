import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_paths.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_file.dart';
import '../../services/llm/llm_models.dart';
import '../../services/llm/llm_service.dart';
import '../../state/app_state.dart';

class MaskEditorDialog extends StatefulWidget {
  final AppFile sourceImage;

  const MaskEditorDialog({super.key, required this.sourceImage});

  @override
  State<MaskEditorDialog> createState() => _MaskEditorDialogState();
}

class _MaskEditorDialogState extends State<MaskEditorDialog> {
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

  @override
  void initState() {
    super.initState();
    _loadImage();
    
    // Auto-select first available multimodal model
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.imageModels.isNotEmpty) {
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

  Future<void> _loadImage() async {
    final bytes = await File(widget.sourceImage.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _imageInfo = frame.image;
        _isLoading = false;
      });
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

  Future<void> _generateAIMask() async {
    final prompt = _aiPromptController.text.trim();
    if (prompt.isEmpty) return;

    if (_selectedModelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No AI model selected. Please configure a model first.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isGeneratingMask = true);

    try {
      final imageBytes = await File(widget.sourceImage.path).readAsBytes();
      final mimeType = p.extension(widget.sourceImage.path).toLowerCase().replaceAll('.', 'image/');

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
            isPolygon: true, // Special flag we'll add to DrawingPath
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
      
      // We want the output to be exactly the same size as the source image
      double pixelRatio = _imageInfo!.width / boundary.size.width;
      
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveMask() async {
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
      final fileName = 'mask_${p.basenameWithoutExtension(widget.sourceImage.path)}_$timestamp.png';
      final filePath = p.join(maskDir.path, fileName);
      
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);

      final maskFile = AppFile(path: filePath, name: fileName);
      appState.galleryState.addDroppedFiles([maskFile]);
      appState.galleryState.toggleImageSelection(maskFile);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.renameSuccess), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportMask() async {
    try {
      final pngBytes = await _captureMask();
      if (pngBytes == null) throw Exception("Failed to capture mask");

      final fileName = 'mask_${p.basenameWithoutExtension(widget.sourceImage.path)}.png';
      
      final String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Mask',
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: ['png'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(pngBytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mask exported to $result'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting mask: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final isControlPressed = HardwareKeyboard.instance.isControlPressed || 
                                 HardwareKeyboard.instance.isMetaPressed;
          if (isControlPressed && event.logicalKey == LogicalKeyboardKey.keyZ) {
            _undo();
          }
        }
      },
      child: Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Column(
              children: [
                // Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    children: [
                      if (!isMobile) ...[
                        Text(l10n.maskEditor, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 16),
                      ],
                      
                      // AI Toggle
                      Tooltip(
                        message: "AI Smart Mask",
                        child: IconButton(
                          icon: Icon(Icons.auto_awesome, color: _showAIPanel ? colorScheme.primary : colorScheme.onSurface),
                          onPressed: () => setState(() => _showAIPanel = !_showAIPanel),
                        ),
                      ),
                      
                      const VerticalDivider(),

                      // Mode Toggle
                      Tooltip(
                        message: "Binary Mask Mode (B&W)",
                        child: IconButton(
                          icon: Icon(
                            _isBinaryMode ? Icons.contrast : Icons.image,
                            color: _isBinaryMode ? colorScheme.primary : colorScheme.onSurface,
                          ),
                          onPressed: () => setState(() => _isBinaryMode = !_isBinaryMode),
                        ),
                      ),
                      const VerticalDivider(),
    
                      // Color Picker
                      _buildColorCircle(Colors.black, l10n.black),
                      _buildColorCircle(Colors.white, l10n.white),
                      if (!_isBinaryMode) ...[
                        _buildColorCircle(Colors.red, l10n.red),
                        _buildColorCircle(Colors.green, l10n.green),
                      ],
                      
                      const VerticalDivider(),
                      
                      // Brush Size
                      Icon(Icons.brush, size: 16, color: Theme.of(context).colorScheme.outline),
                      SizedBox(
                        width: isMobile ? 80 : 150,
                        child: Slider(
                          value: _brushSize,
                          min: 1,
                          max: 100,
                          onChanged: (v) => setState(() => _brushSize = v),
                        ),
                      ),
                      
                      const Spacer(),
                      
                      IconButton(
                        icon: const Icon(Icons.undo),
                        onPressed: _paths.isEmpty ? null : _undo,
                        tooltip: l10n.undo,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _paths.isEmpty ? null : _clear,
                        tooltip: l10n.clear,
                      ),
                      const SizedBox(width: 8),
                      
                      // Export Button
                      IconButton(
                        icon: const Icon(Icons.save_alt),
                        onPressed: _exportMask,
                        tooltip: "Export to File",
                      ),
                      const SizedBox(width: 8),
                      
                      FilledButton.icon(
                        onPressed: _saveMask,
                        icon: const Icon(Icons.check),
                        label: Text(isMobile ? l10n.apply : l10n.saveAndSelect),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                
                // Drawing Area
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                      maxScale: 5.0,
                      minScale: 0.1,
                      child: AspectRatio(
                        aspectRatio: _imageInfo!.width / _imageInfo!.height,
                        child: RepaintBoundary(
                          key: _repaintKey,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Base Layer
                              if (_isBinaryMode)
                                Container(color: Colors.black)
                              else
                                Image.file(File(widget.sourceImage.path), fit: BoxFit.fill),
                              
                              // Drawing Layer
                              MouseRegion(
                                cursor: SystemMouseCursors.none,
                                onHover: (event) {
                                  setState(() {
                                    _mousePosition = event.localPosition;
                                  });
                                },
                                onExit: (event) {
                                  setState(() {
                                    _mousePosition = null;
                                  });
                                },
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
                                  onPanEnd: (_) {
                                    // Keep the mouse visible even when not panning
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
                                    size: Size.infinite,
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
              ],
            ),
            
            // AI Panel Overlay
            if (_showAIPanel)
              Positioned(
                top: 60,
                left: 16,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  color: colorScheme.surface,
                  child: Container(
                    width: 300,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("AI Smart Mask", style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                        const SizedBox(height: 8),
                        
                        // Model Selector
                        Consumer<AppState>(
                          builder: (context, appState, _) {
                            final models = appState.imageModels;
                            return DropdownButtonFormField<String>(
                              value: _selectedModelId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Select Model',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: models.map((m) => DropdownMenuItem(
                                value: m.modelId,
                                child: Text(m.modelName.isNotEmpty ? m.modelName : m.modelId, overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedModelId = val);
                              },
                            );
                          }
                        ),
                        const SizedBox(height: 12),

                        Text("Detail Level (Points: ${_pointCount.toInt()}):", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        SizedBox(
                          height: 36,
                          child: Slider(
                            value: _pointCount,
                            min: 10,
                            max: 500,
                            divisions: 49,
                            label: _pointCount.toInt().toString(),
                            onChanged: (v) => setState(() => _pointCount = v),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text("Describe what to mask (e.g., 'the red car', 'the cat'):", style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _aiPromptController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            hintText: "Enter prompt...",
                          ),
                          onSubmitted: (_) => _generateAIMask(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isGeneratingMask ? null : _generateAIMask,
                            icon: _isGeneratingMask 
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.auto_awesome, size: 16),
                            label: Text(_isGeneratingMask ? "Generating..." : "Generate Mask"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorCircle(Color color, String tooltip) {
    bool isSelected = _selectedColor == color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () => setState(() => _selectedColor = color),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)] : null,
            ),
          ),
        ),
      ),
    );
  }
}

class DrawingPath {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isPolygon;

  DrawingPath({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isPolygon = false,
  });
}

class MaskPainter extends CustomPainter {
  final List<DrawingPath> paths;

  MaskPainter({required this.paths});

  @override
  void paint(Canvas canvas, Size size) {
    for (var drawingPath in paths) {
      final paint = Paint()
        ..color = drawingPath.color
        ..strokeWidth = drawingPath.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = drawingPath.isPolygon ? PaintingStyle.fill : PaintingStyle.stroke;

      if (drawingPath.points.length > 1) {
        final path = Path();
        path.moveTo(drawingPath.points.first.dx, drawingPath.points.first.dy);
        for (int i = 1; i < drawingPath.points.length; i++) {
          path.lineTo(drawingPath.points[i].dx, drawingPath.points[i].dy);
        }
        if (drawingPath.isPolygon) {
          path.close();
        }
        canvas.drawPath(path, paint);
      } else if (drawingPath.points.isNotEmpty && !drawingPath.isPolygon) {
        canvas.drawCircle(drawingPath.points.first, drawingPath.strokeWidth / 2, paint..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant MaskPainter oldDelegate) => true;
}

class BrushPreviewPainter extends CustomPainter {
  final Offset position;
  final double size;
  final Color color;

  BrushPreviewPainter({required this.position, required this.size, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = color == Colors.black ? Colors.white : Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(position, this.size / 2, paint);
    canvas.drawCircle(position, this.size / 2, borderPaint);
  }

  @override
  bool shouldRepaint(covariant BrushPreviewPainter oldDelegate) {
    return oldDelegate.position != position || oldDelegate.size != size || oldDelegate.color != color;
  }
}
