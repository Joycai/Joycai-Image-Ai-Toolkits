import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/window_state.dart';

class FloatingPreviewHost extends StatelessWidget {
  const FloatingPreviewHost({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild only when windows are added or removed
    return Selector<WindowState, int>(
      selector: (_, state) => state.floatingPreviews.length,
      builder: (context, _, __) {
        final windowState = Provider.of<WindowState>(context, listen: false);
        
        return Stack(
          children: windowState.floatingPreviews.map((preview) {
            return FloatingPreviewWindow(
              key: ValueKey(preview.id),
              preview: preview,
            );
          }).toList(),
        );
      },
    );
  }
}

class FloatingPreviewWindow extends StatefulWidget {
  final PreviewWindowState preview;

  const FloatingPreviewWindow({
    super.key, 
    required this.preview,
  });

  @override
  State<FloatingPreviewWindow> createState() => _FloatingPreviewWindowState();
}

class _FloatingPreviewWindowState extends State<FloatingPreviewWindow> {
  bool _isInteracting = false;

  @override
  Widget build(BuildContext context) {
    // Listen to changes in WindowState to update position/size
    return Consumer<WindowState>(
      builder: (context, windowState, child) {
        final preview = widget.preview;
        final screenSize = MediaQuery.of(context).size;

        // Position calculation
        final double targetX = preview.isMinimized ? screenSize.width / 2 - (preview.size.width / 2) : preview.position.dx;
        final double targetY = preview.isMinimized ? screenSize.height + 200 : preview.position.dy;

        // Only animate when NOT dragging/resizing
        final duration = _isInteracting ? Duration.zero : const Duration(milliseconds: 400);

        return AnimatedPositioned(
          duration: duration,
          curve: Curves.fastOutSlowIn,
          left: targetX,
          top: targetY,
          child: IgnorePointer(
            ignoring: preview.isMinimized,
            child: AnimatedScale(
              duration: duration,
              scale: preview.isMinimized ? 0.1 : 1.0,
              curve: Curves.fastOutSlowIn,
              child: AnimatedOpacity(
                duration: duration,
                opacity: preview.isMinimized ? 0.0 : 1.0,
                child: RepaintBoundary(
                  child: child!,
                ),
              ),
            ),
          ),
        );
      },
      // The heavy content is kept in the child of Consumer so it doesn't rebuild on every drag update
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: Colors.black,
        child: _PreviewWindowContent(preview: widget.preview, 
          onInteractionStart: () => setState(() => _isInteracting = true),
          onInteractionEnd: () => setState(() => _isInteracting = false),
        ),
      ),
    );
  }
}

class _PreviewWindowContent extends StatelessWidget {
  final PreviewWindowState preview;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  const _PreviewWindowContent({
    required this.preview,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
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
            onPanStart: (_) => onInteractionStart(),
            onPanUpdate: preview.isMaximized ? null : (details) {
              windowState.updateFloatingPreviewPosition(
                preview.id,
                preview.position + details.delta,
              );
            },
            onPanEnd: (_) => onInteractionEnd(),
            onDoubleTap: () {
              final size = MediaQuery.of(context).size;
              windowState.toggleMaximizeFloatingPreview(preview.id, size);
            },
            onTapDown: (_) => windowState.bringToFront(preview.id),
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
                    icon: const Icon(Icons.remove, size: 18),
                    tooltip: 'Minimize',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => windowState.toggleMinimizeFloatingPreview(preview.id),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(preview.isMaximized ? Icons.fullscreen_exit : Icons.fullscreen, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      final size = MediaQuery.of(context).size;
                      windowState.toggleMaximizeFloatingPreview(preview.id, size);
                    },
                  ),
                  const SizedBox(width: 8),
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
                if (!preview.isMaximized)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanStart: (_) => onInteractionStart(),
                      onPanUpdate: (details) {
                        final newWidth = (preview.size.width + details.delta.dx).clamp(200.0, 1600.0);
                        final newHeight = (preview.size.height + details.delta.dy).clamp(150.0, 1200.0);
                        windowState.updateFloatingPreviewSize(preview.id, Size(newWidth, newHeight));
                      },
                      onPanEnd: (_) => onInteractionEnd(),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(20),
                            borderRadius: const BorderRadius.only(bottomRight: Radius.circular(12)),
                          ),
                          child: const Icon(Icons.south_east, size: 14, color: Colors.white54),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
