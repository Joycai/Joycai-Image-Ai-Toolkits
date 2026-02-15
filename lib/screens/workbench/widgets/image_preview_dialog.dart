import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/window_state.dart';

class ImagePreviewDialog extends StatelessWidget {
  final String initialPath;

  const ImagePreviewDialog({
    super.key,
    required this.initialPath,
  });

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (windowState.openedPreviewPaths.isEmpty && !windowState.openedPreviewPaths.contains(initialPath)) {
       // Safety fallback if opened from somewhere that didn't add to windowState
       // But we should usually add it before opening.
    }

    final activeIndex = windowState.activePreviewIndex.clamp(0, windowState.openedPreviewPaths.length - 1);
    final activePath = windowState.openedPreviewPaths[activeIndex];

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Column(
        children: [
          // AppBar
          AppBar(
            backgroundColor: Colors.black.withAlpha(150),
            foregroundColor: Colors.white,
            title: Text(activePath.split(Platform.pathSeparator).last, style: const TextStyle(fontSize: 14)),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.zoom_out_map),
                onPressed: () {
                  // Reset zoom logic could go here if using a controller
                },
              ),
            ],
          ),

          // Main Viewer
          Expanded(
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 10.0,
              child: Center(
                child: Image.file(
                  File(activePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),

          // Thumbnail Strip
          if (windowState.openedPreviewPaths.length > 1)
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.black.withAlpha(200),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: windowState.openedPreviewPaths.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final path = windowState.openedPreviewPaths[index];
                  final isSelected = index == activeIndex;
                  
                  return GestureDetector(
                    onTap: () => windowState.setActivePreview(index),
                    child: Container(
                      width: 76,
                      decoration: BoxDecoration(
                        border: isSelected 
                            ? Border.all(color: colorScheme.primary, width: 3)
                            : Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Image.file(
                              File(path),
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () {
                                if (windowState.openedPreviewPaths.length == 1) {
                                  Navigator.of(context).pop();
                                }
                                windowState.closePreview(index);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

void showImagePreview(BuildContext context, String path) {
  final windowState = Provider.of<WindowState>(context, listen: false);
  windowState.openPreview(path);
  
  showDialog(
    context: context,
    builder: (context) => ImagePreviewDialog(initialPath: path),
  );
}
