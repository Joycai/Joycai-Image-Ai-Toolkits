import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/window_state.dart';

class ComparatorView extends StatefulWidget {
  const ComparatorView({super.key});

  @override
  State<ComparatorView> createState() => _ComparatorViewState();
}

class _ComparatorViewState extends State<ComparatorView> {
  final TransformationController _controller1 = TransformationController();
  final TransformationController _controller2 = TransformationController();
  double _scanRatio = 0.5;

  @override
  void initState() {
    super.initState();
    _controller1.addListener(_syncControllers);
  }

  void _syncControllers() {
    if (_controller1.value != _controller2.value) {
      _controller2.value = _controller1.value;
    }
  }

  @override
  void dispose() {
    _controller1.removeListener(_syncControllers);
    _controller1.dispose();
    _controller2.dispose();
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
              l10n.sendToComparator, // Using existing string as fallback or placeholder
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.selectFromLibrary,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Content
        Expanded(
          child: Container(
            color: Colors.black,
            child: windowState.isComparatorSyncMode 
              ? _buildSyncView(windowState) 
              : _buildSwapView(windowState),
          ),
        ),
        
        // Footer Info (Basic status bar for now)
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
        Expanded(
          child: _buildViewer(
            windowState.comparatorRawPath, 
            "RAW", 
            _controller1, 
            borderColor: Colors.blueAccent
          )
        ),
        const VerticalDivider(width: 1, color: Colors.white24),
        Expanded(
          child: _buildViewer(
            windowState.comparatorAfterPath, 
            "AFTER", 
            _controller2, 
            borderColor: Colors.orangeAccent
          )
        ),
      ],
    );
  }

  Widget _buildSwapView(WindowState windowState) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Handle mouse movement for scan line
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
              _buildViewer(windowState.comparatorAfterPath, "AFTER", _controller1, showLabel: false),
              
              // Top Layer: Raw (Clipped)
              ClipRect(
                clipper: _CurtainClipper(_scanRatio),
                child: _buildViewer(windowState.comparatorRawPath, "RAW", _controller1, showLabel: false), // Share controller for perfect sync
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
                child: _buildLabelBadge("RAW", Colors.blueAccent, opacity: (1.0 - _scanRatio).clamp(0.4, 1.0)),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: _buildLabelBadge("AFTER", Colors.orangeAccent, opacity: _scanRatio.clamp(0.4, 1.0)),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildLabelBadge(String label, Color color, {double opacity = 1.0}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha((255 * opacity).round()),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildViewer(String? path, String label, TransformationController controller, {bool showLabel = true, Color? borderColor}) {
    if (path == null) {
      return Center(child: Text('No image', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 12)));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          transformationController: controller,
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
              decoration: BoxDecoration(
                color: borderColor ?? Colors.black54, 
                borderRadius: BorderRadius.circular(4)
              ),
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
