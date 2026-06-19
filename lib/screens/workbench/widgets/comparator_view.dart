import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/workbench_ui_state.dart';

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
    final workbenchUIState = Provider.of<WorkbenchUIState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    if (workbenchUIState.comparatorRawPath == null && workbenchUIState.comparatorAfterPath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.compare, size: 64, color: colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              l10n.sendToComparator,
              style: TextStyle(fontSize: 16, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.selectFromLibrary,
              style: TextStyle(fontSize: 14, color: colorScheme.outline),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDropHintCard(l10n.labelRaw, colorScheme.primaryContainer, colorScheme.onPrimaryContainer, Icons.photo_outlined),
                const SizedBox(width: 16),
                _buildDropHintCard(l10n.labelAfter, colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer, Icons.auto_fix_high),
              ],
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
            child: workbenchUIState.isComparatorSyncMode 
              ? _buildSyncView(workbenchUIState) 
              : _buildSwapView(workbenchUIState),
          ),
        ),
        
        // Footer
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: colorScheme.surfaceContainer,
          child: Row(
            children: [
              _buildFooterLabel(l10n.labelRaw, colorScheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  workbenchUIState.comparatorRawPath?.split(Platform.pathSeparator).last ?? '—',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _buildFooterLabel(l10n.labelAfter, colorScheme.tertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  workbenchUIState.comparatorAfterPath?.split(Platform.pathSeparator).last ?? '—',
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

  Widget _buildSyncView(WorkbenchUIState workbenchUIState) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _buildViewer(
            workbenchUIState.comparatorRawPath,
            "RAW",
            _controller1,
            borderColor: colorScheme.primary,
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.white24),
        Expanded(
          child: _buildViewer(
            workbenchUIState.comparatorAfterPath,
            "AFTER",
            _controller2,
            borderColor: colorScheme.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildSwapView(WorkbenchUIState workbenchUIState) {
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
              _buildViewer(workbenchUIState.comparatorAfterPath, "AFTER", _controller1, showLabel: false),
              
              // Top Layer: Raw (Clipped)
              ClipRect(
                clipper: _CurtainClipper(_scanRatio),
                child: _buildViewer(workbenchUIState.comparatorRawPath, "RAW", _controller1, showLabel: false), // Share controller for perfect sync
              ),

              // Scanning Line & Handle
              Positioned(
                top: 0,
                bottom: 0,
                left: constraints.maxWidth * _scanRatio - 20, // Wider hit area
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      double newPos = constraints.maxWidth * _scanRatio + details.delta.dx;
                      _scanRatio = (newPos / constraints.maxWidth).clamp(0.0, 1.0);
                    });
                  },
                  child: Container(
                    width: 40,
                    color: Colors.transparent,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: Colors.white70,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 4),
                            ],
                          ),
                        ),
                        // Handle icon for touch
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(200),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 4),
                            ],
                          ),
                          child: const RotatedBox(
                            quarterTurns: 1,
                            child: Icon(Icons.unfold_more, size: 16, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Labels
              Builder(
                builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return Stack(
                    children: [
                      Positioned(
                        top: 10,
                        left: 10,
                        child: IgnorePointer(
                          child: _buildLabelBadge("RAW", cs.primary, opacity: (1.0 - _scanRatio).clamp(0.4, 1.0)),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: IgnorePointer(
                          child: _buildLabelBadge("AFTER", cs.tertiary, opacity: _scanRatio.clamp(0.4, 1.0)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildDropHintCard(String label, Color bg, Color fg, IconData icon) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg.withAlpha(180),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: fg),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
        ],
      ),
    );
  }

  Widget _buildFooterLabel(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
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
      return const Center(child: Text('No image', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)));
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
