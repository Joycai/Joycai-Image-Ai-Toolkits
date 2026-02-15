import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/window_state.dart';
import '../../../widgets/drawing_canvas.dart';

class MaskEditorView extends StatefulWidget {
  final List<DrawingPath> paths;
  final Color selectedColor;
  final double brushSize;
  final bool isBinaryMode;
  final GlobalKey repaintKey;
  final Offset? mousePosition;
  final Function(Offset) onPanStart;
  final Function(Offset) onPanUpdate;
  final Function(Offset?) onHover;

  const MaskEditorView({
    super.key,
    required this.paths,
    required this.selectedColor,
    required this.brushSize,
    required this.isBinaryMode,
    required this.repaintKey,
    this.mousePosition,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onHover,
  });

  @override
  State<MaskEditorView> createState() => _MaskEditorViewState();
}

class _MaskEditorViewState extends State<MaskEditorView> {
  ui.Image? _imageInfo;
  bool _isLoading = true;
  String? _lastPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkImageChange();
  }

  Future<void> _checkImageChange() async {
    final windowState = Provider.of<WindowState>(context);
    final sourceImage = windowState.maskEditorSourceImage;

    if (sourceImage != null && sourceImage.path != _lastPath) {
      _lastPath = sourceImage.path;
      await _loadImage(sourceImage.path);
    } else if (sourceImage == null && _lastPath != null) {
      setState(() {
        _imageInfo = null;
        _lastPath = null;
      });
    }
  }

  Future<void> _loadImage(String path) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _imageInfo = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final windowState = Provider.of<WindowState>(context);
    final sourceImage = windowState.maskEditorSourceImage;

    if (sourceImage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.brush, size: 64, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            const Text("No image selected for masking"),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_imageInfo == null) {
      return const Center(child: Text("Failed to load image"));
    }

    return Container(
      color: Colors.black,
      child: InteractiveViewer(
        maxScale: 10.0,
        minScale: 0.1,
        child: Center(
          child: AspectRatio(
            aspectRatio: _imageInfo!.width / _imageInfo!.height,
            child: RepaintBoundary(
              key: widget.repaintKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.isBinaryMode)
                    Container(color: Colors.black)
                  else
                    Image.file(File(sourceImage.path), fit: BoxFit.fill),
                  
                  MouseRegion(
                    cursor: SystemMouseCursors.none,
                    onHover: (event) => widget.onHover(event.localPosition),
                    onExit: (event) => widget.onHover(null),
                    child: GestureDetector(
                      onPanStart: (details) => widget.onPanStart(details.localPosition),
                      onPanUpdate: (details) => widget.onPanUpdate(details.localPosition),
                      child: CustomPaint(
                        painter: MaskPainter(paths: widget.paths),
                        foregroundPainter: widget.mousePosition != null 
                          ? BrushPreviewPainter(
                              position: widget.mousePosition!, 
                              size: widget.brushSize,
                              color: widget.selectedColor,
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
    );
  }
}
