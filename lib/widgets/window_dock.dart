import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/window_state.dart';

class WindowDock extends StatelessWidget {
  const WindowDock({super.key});

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    final minimizedPreviews = windowState.floatingPreviews.where((p) => p.isMinimized).toList();
    final isComparatorMinimized = windowState.isComparatorMinimized;

    if (minimizedPreviews.isEmpty && !isComparatorMinimized) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(200),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: colorScheme.outlineVariant.withAlpha(100)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isComparatorMinimized)
                    _DockTile(
                      icon: Icons.compare,
                      color: colorScheme.secondary,
                      label: 'Comparator',
                      onTap: () => windowState.toggleMinimizeComparator(),
                      onClose: () => windowState.closeComparator(),
                    ),
                  
                  ...minimizedPreviews.map((p) => _DockTile(
                    imagePath: p.imagePath,
                    icon: Icons.image_outlined,
                    color: colorScheme.primary,
                    label: p.imagePath.split(Platform.pathSeparator).last,
                    onTap: () => windowState.toggleMinimizeFloatingPreview(p.id),
                    onClose: () => windowState.closeFloatingPreview(p.id),
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockTile extends StatelessWidget {
  final String? imagePath;
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _DockTile({
    this.imagePath,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Tooltip(
        message: label,
        child: Stack(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withAlpha(100)),
                ),
                child: ClipOval(
                  child: imagePath != null
                    ? Image.file(File(imagePath!), fit: BoxFit.cover)
                    : Icon(icon, color: color, size: 20),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
