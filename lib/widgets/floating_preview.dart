import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/window_state.dart';

class FloatingPreviewHost extends StatelessWidget {
  const FloatingPreviewHost({super.key});

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context);
    
    return Stack(
      children: windowState.floatingPreviews.map((preview) {
        return Positioned(
          left: preview.position.dx,
          top: preview.position.dy,
          child: FloatingPreviewWindow(preview: preview),
        );
      }).toList(),
    );
  }
}

class FloatingPreviewWindow extends StatelessWidget {
  final PreviewWindowState preview;

  const FloatingPreviewWindow({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTapDown: (_) => windowState.bringToFront(preview.id),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: Colors.black,
        child: Container(
          width: preview.size.width,
          height: preview.size.height,
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.primary.withAlpha(100), width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Title Bar / Drag Handle
              GestureDetector(
                onPanUpdate: (details) {
                  windowState.updateFloatingPreviewPosition(
                    preview.id,
                    preview.position + details.delta,
                  );
                },
                onDoubleTap: () {
                  windowState.updateFloatingPreviewSize(preview.id, const Size(400, 300));
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: colorScheme.surfaceContainerHigh,
                  child: Row(
                    children: [
                      Icon(Icons.image_outlined, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          preview.imagePath.split(Platform.pathSeparator).last,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => windowState.closeFloatingPreview(preview.id),
                      ),
                    ],
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Stack(
                  children: [
                    InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.1,
                      maxScale: 5.0,
                      child: Center(
                        child: Image.file(
                          File(preview.imagePath),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    // Resize Handle
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          final newWidth = (preview.size.width + details.delta.dx).clamp(200.0, 1200.0);
                          final newHeight = (preview.size.height + details.delta.dy).clamp(150.0, 1000.0);
                          windowState.updateFloatingPreviewSize(preview.id, Size(newWidth, newHeight));
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeDownRight,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(30),
                              borderRadius: const BorderRadius.only(bottomRight: Radius.circular(12)),
                            ),
                            child: const Icon(Icons.south_east, size: 12, color: Colors.white54),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
