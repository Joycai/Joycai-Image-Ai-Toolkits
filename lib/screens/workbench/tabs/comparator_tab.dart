import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/window_state.dart';

class ComparatorTab extends StatefulWidget {
  const ComparatorTab({super.key});

  @override
  State<ComparatorTab> createState() => _ComparatorTabState();
}

class _ComparatorTabState extends State<ComparatorTab> {
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

    if (windowState.comparatorRawPath == null && windowState.comparatorAfterPath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.compare, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              "No images in comparator",
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              "Send images here from the gallery",
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Text('Image Comparator', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
              const Spacer(),
               // Mode Toggle
              ToggleButtons(
                isSelected: [windowState.isComparatorSyncMode, !windowState.isComparatorSyncMode],
                onPressed: (index) {
                  if (windowState.isComparatorSyncMode != (index == 0)) {
                    windowState.toggleComparatorMode();
                  }
                },
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minHeight: 32, minWidth: 48),
                children: [
                  Tooltip(message: l10n.compareModeSync, child: const Icon(Icons.view_column, size: 18)),
                  Tooltip(message: l10n.compareModeSwap, child: const Icon(Icons.view_stream, size: 18)),
                ],
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: Container(
            color: Colors.black,
            child: windowState.isComparatorSyncMode 
              ? _buildSyncView(windowState) 
              : _buildSwapView(windowState),
          ),
        ),
        
        // Footer Info
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: colorScheme.surfaceContainer,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 12, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Raw: ${windowState.comparatorRawPath?.split(Platform.pathSeparator).last ?? "N/A"} | After: ${windowState.comparatorAfterPath?.split(Platform.pathSeparator).last ?? "N/A"}',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
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
      return Center(child: Text('No image', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 12)));
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
