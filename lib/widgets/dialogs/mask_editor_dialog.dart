import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_paths.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_file.dart';
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

  @override
  void initState() {
    super.initState();
    _loadImage();
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

  Future<void> _saveMask() async {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context, listen: false);
    
    try {
      RenderRepaintBoundary boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      // We want the output to be exactly the same size as the source image
      double pixelRatio = _imageInfo!.width / boundary.size.width;
      
      ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final dataDir = await AppPaths.getDataDirectory();
      final maskDir = Directory(p.join(dataDir, 'masks'));
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 700;

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
        child: Column(
          children: [
            // Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  if (!isMobile) ...[
                    Text(l10n.maskEditor, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                  ],
                  
                  // Color Picker
                  _buildColorCircle(Colors.black, l10n.black),
                  _buildColorCircle(Colors.white, l10n.white),
                  _buildColorCircle(Colors.red, l10n.red),
                  _buildColorCircle(Colors.green, l10n.green),
                  
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
                          // Base Image
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

  DrawingPath({required this.points, required this.color, required this.strokeWidth});
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
        ..style = PaintingStyle.stroke;

      if (drawingPath.points.length > 1) {
        final path = Path();
        path.moveTo(drawingPath.points.first.dx, drawingPath.points.first.dy);
        for (int i = 1; i < drawingPath.points.length; i++) {
          path.lineTo(drawingPath.points[i].dx, drawingPath.points[i].dy);
        }
        canvas.drawPath(path, paint);
      } else if (drawingPath.points.isNotEmpty) {
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
