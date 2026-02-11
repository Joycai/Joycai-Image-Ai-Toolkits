import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/window_state.dart';

class PreviewTab extends StatelessWidget {
  const PreviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (windowState.openedPreviewPaths.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            const Text(
              "No images opened in preview",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final activeIndex = windowState.activePreviewIndex.clamp(0, windowState.openedPreviewPaths.length - 1);
    final activePath = windowState.openedPreviewPaths[activeIndex];

    return Column(
      children: [
        // Main Viewer
        Expanded(
          child: Container(
            color: Colors.black,
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 5.0,
              child: Center(
                child: Image.file(
                  File(activePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
          ),
        ),
        
        // Thumbnail Strip
        Container(
          height: 80,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: colorScheme.surface,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: windowState.openedPreviewPaths.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final path = windowState.openedPreviewPaths[index];
              final isSelected = index == activeIndex;
              
              return GestureDetector(
                onTap: () => windowState.setActivePreview(index),
                child: Container(
                  width: 64,
                  decoration: BoxDecoration(
                    border: isSelected 
                        ? Border.all(color: colorScheme.primary, width: 2)
                        : Border.all(color: colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => windowState.closePreview(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 12, color: Colors.white),
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
    );
  }
}
