import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../state/window_state.dart';

class FloatingComparatorHost extends StatelessWidget {
  const FloatingComparatorHost({super.key});

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context);
    if (!windowState.isComparatorOpen) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned(
          left: windowState.comparatorPosition.dx,
          top: windowState.comparatorPosition.dy,
          child: const FloatingComparatorWindow(),
        ),
      ],
    );
  }
}

class FloatingComparatorWindow extends StatefulWidget {
  const FloatingComparatorWindow({super.key});

  @override
  State<FloatingComparatorWindow> createState() => _FloatingComparatorWindowState();
}

class _FloatingComparatorWindowState extends State<FloatingComparatorWindow> {
  final TransformationController _sharedController = TransformationController();
  double _scanRatio = 0.5;

  @override
  void dispose() {
    _sharedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final windowState = Provider.of<WindowState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: Colors.black,
      child: Container(
        width: windowState.comparatorSize.width,
        height: windowState.comparatorSize.height,
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.secondary.withAlpha(150), width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Title Bar
            GestureDetector(
              onPanUpdate: (details) {
                windowState.updateComparatorPosition(windowState.comparatorPosition + details.delta);
              },
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: colorScheme.surfaceContainerHigh,
                child: Row(
                  children: [
                    Icon(Icons.compare, size: 18, color: colorScheme.secondary),
                    const SizedBox(width: 8),
                    const Text('Image Comparator', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    // Mode Toggle
                    TextButton.icon(
                      onPressed: windowState.toggleComparatorMode,
                      icon: Icon(windowState.isComparatorSyncMode ? Icons.view_column : Icons.view_stream, size: 16),
                      label: Text(
                        windowState.isComparatorSyncMode ? l10n.compareModeSync : l10n.compareModeSwap,
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                    const VerticalDivider(width: 20, indent: 10, endIndent: 10),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: windowState.closeComparator,
                    ),
                  ],
                ),
              ),
            ),
            // Content
            Expanded(
              child: windowState.isComparatorSyncMode ? _buildSyncView(windowState) : _buildSwapView(windowState),
            ),
            // Footer Info
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.black54,
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 12, color: Colors.white54),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Raw: ${windowState.comparatorRawPath?.split(Platform.pathSeparator).last ?? "N/A"} | After: ${windowState.comparatorAfterPath?.split(Platform.pathSeparator).last ?? "N/A"}',
                      style: const TextStyle(color: Colors.white54, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Resize Handle
                  GestureDetector(
                    onPanUpdate: (details) {
                      final newWidth = (windowState.comparatorSize.width + details.delta.dx).clamp(400.0, 1600.0);
                      final newHeight = (windowState.comparatorSize.height + details.delta.dy).clamp(300.0, 1200.0);
                      windowState.updateComparatorSize(Size(newWidth, newHeight));
                    },
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: Icon(Icons.south_east, size: 14, color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncView(WindowState windowState) {
    return Row(
      children: [
        Expanded(child: _buildViewer(windowState.comparatorRawPath, "RAW")),
        const VerticalDivider(width: 1, color: Colors.white24),
        Expanded(child: _buildViewer(windowState.comparatorAfterPath, "AFTER")),
      ],
    );
  }

  Widget _buildSwapView(WindowState windowState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) {
            setState(() {
              _scanRatio = (event.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bottom Layer: After
              _buildViewer(windowState.comparatorAfterPath, "AFTER", showLabel: false),
              
              // Top Layer: Raw (Clipped)
              ClipRect(
                clipper: _CurtainClipper(_scanRatio),
                child: _buildViewer(windowState.comparatorRawPath, "RAW", showLabel: false),
              ),

              // Scanning Line
              Positioned(
                top: 0,
                bottom: 0,
                left: constraints.maxWidth * _scanRatio - 1,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: Colors.white70,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 4),
                    ],
                  ),
                ),
              ),

              // Labels
              Positioned(
                top: 10,
                left: 10,
                child: _buildLabelBadge("RAW", opacity: (1.0 - _scanRatio).clamp(0.2, 0.8)),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: _buildLabelBadge("AFTER", opacity: _scanRatio.clamp(0.2, 0.8)),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildLabelBadge(String label, {double opacity = 0.5}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha((255 * opacity).round()),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildViewer(String? path, String label, {bool showLabel = true}) {
    if (path == null) {
      return Center(child: Text('Drag image here or\nselect from menu', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 12)));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          transformationController: _sharedController,
          panEnabled: true,
          minScale: 0.1,
          maxScale: 10.0,
          child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
        ),
        if (showLabel)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}

class _CurtainClipper extends CustomClipper<Rect> {
  final double ratio;
  _CurtainClipper(this.ratio);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, size.width * ratio, size.height);
  }

  @override
  bool shouldReclip(_CurtainClipper oldClipper) => oldClipper.ratio != ratio;
}