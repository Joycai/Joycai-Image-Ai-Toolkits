import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/drawing_canvas.dart';
import 'canvas_overlays.dart';

/// Radius of the image plate on the canvas — the same smallest step the
/// comparator's panes take, so a picture sitting on a workbench canvas has one
/// shape across the tools.
const double _kCanvasImageRadius = AppRadius.xs;

class MaskEditorView extends StatefulWidget {
  final List<DrawingPath> paths;

  /// Ticks whenever [paths] changes.
  ///
  /// The list is mutated in place while a stroke is being drawn, so there is
  /// nothing about the list itself for the canvas to compare against — this is
  /// what tells it to repaint. A notifier rather than a rebuild from above
  /// because the screen that owns the strokes draws the whole workbench, and a
  /// stroke is a drag: see `_WorkbenchScreenState._maskRevision`.
  final ValueListenable<int> revision;

  final Color selectedColor;
  final double brushSize;
  final bool isBinaryMode;
  final GlobalKey repaintKey;

  /// Where the pointer is, or null when it has left the canvas. Drives the
  /// brush preview only, and moves at pointer rate — hence a notifier.
  final ValueListenable<Offset?> mousePosition;

  final Function(Offset) onPanStart;
  final Function(Offset) onPanUpdate;
  final Function(Offset?) onHover;

  const MaskEditorView({
    super.key,
    required this.paths,
    required this.revision,
    required this.selectedColor,
    required this.brushSize,
    required this.isBinaryMode,
    required this.repaintKey,
    required this.mousePosition,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onHover,
  });

  @override
  State<MaskEditorView> createState() => _MaskEditorViewState();
}

class _MaskEditorViewState extends State<MaskEditorView> {
  final TransformationController _controller = TransformationController();

  ui.Image? _imageInfo;
  bool _isLoading = true;
  String? _lastPath;

  /// The two canvas notifiers as one listenable, merged once rather than per
  /// build — `Listenable.merge` allocates, and re-allocating it every build
  /// would re-subscribe on every frame of a stroke.
  late Listenable _canvasRepaint;

  @override
  void initState() {
    super.initState();
    _canvasRepaint = Listenable.merge([widget.revision, widget.mousePosition]);
  }

  @override
  void didUpdateWidget(covariant MaskEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.mousePosition != widget.mousePosition) {
      _canvasRepaint = Listenable.merge([widget.revision, widget.mousePosition]);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkImageChange();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkImageChange() async {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context);
    final sourceImage = workbenchUIState.maskEditorSourceImage;

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

  /// Zooms about the middle of the viewport rather than the scene's origin —
  /// scaling the raw matrix walks the picture off the top-left corner, which
  /// is what a `+` button that "loses" the image is doing.
  void _setScale(double target, Size viewport) {
    final matrix = _controller.value.clone();
    final current = matrix.getMaxScaleOnAxis();
    final factor = target.clamp(0.1, 10.0) / current;
    if ((factor - 1).abs() < 0.001) return;

    final scenePoint = _controller.toScene(Offset(viewport.width / 2, viewport.height / 2));
    matrix
      ..translateByDouble(scenePoint.dx, scenePoint.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
    _controller.value = matrix;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final workbenchUIState = Provider.of<WorkbenchUIState>(context);
    final sourceImage = workbenchUIState.maskEditorSourceImage;

    // The output strip stays whatever the canvas is showing: it is the
    // screen's chrome, not a result panel, and a bar that appears only once an
    // image arrives makes the whole layout jump under the user.
    return Column(
      children: [
        Expanded(
          child: Container(
            color: colorScheme.surfaceContainerHigh,
            child: sourceImage == null
                ? _buildEmptyState(l10n, colorScheme)
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _imageInfo == null
                        ? Center(
                            child: Text(
                              l10n.imageLoadFailed,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          )
                        : _buildCanvas(sourceImage.path, l10n, colorScheme),
          ),
        ),
        _MaskOutputBar(
          image: _imageInfo,
          isBinaryMode: widget.isBinaryMode,
          l10n: l10n,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.dialog),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Icon(Icons.brush_outlined, size: 28, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          Text(l10n.noImagesSelected, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          AppButton(
            label: l10n.goToGallery,
            icon: Icons.photo_library_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(String path, AppLocalizations l10n, ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                maxScale: 10.0,
                minScale: 0.1,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: AspectRatio(
                      aspectRatio: _imageInfo!.width / _imageInfo!.height,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(_kCanvasImageRadius),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.18),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(_kCanvasImageRadius),
                          // The boundary is inside the clip and outside the
                          // shadow: the export is the picture and the strokes,
                          // never the canvas dressing around them.
                          child: RepaintBoundary(
                            key: widget.repaintKey,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (widget.isBinaryMode)
                                  const ColoredBox(color: Colors.black)
                                else
                                  Image.file(File(path), fit: BoxFit.fill),
                                MouseRegion(
                                  cursor: SystemMouseCursors.none,
                                  onHover: (event) => widget.onHover(event.localPosition),
                                  onExit: (event) => widget.onHover(null),
                                  child: GestureDetector(
                                    onPanStart: (details) => widget.onPanStart(details.localPosition),
                                    onPanUpdate: (details) => widget.onPanUpdate(details.localPosition),
                                    // Its own boundary inside the export one:
                                    // strokes and the brush preview repaint
                                    // without dragging the picture underneath
                                    // through the rasteriser with them. The
                                    // export still captures both — a nested
                                    // boundary is part of the subtree
                                    // `toImage` composites.
                                    child: RepaintBoundary(
                                      child: ListenableBuilder(
                                        listenable: _canvasRepaint,
                                        builder: (context, _) {
                                          final mouse = widget.mousePosition.value;
                                          return CustomPaint(
                                            painter: MaskPainter(paths: widget.paths),
                                            foregroundPainter: mouse != null
                                                ? BrushPreviewPainter(
                                                    position: mouse,
                                                    size: widget.brushSize,
                                                    color: widget.selectedColor,
                                                  )
                                                : null,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // What the brush will lay down, over the canvas' top-left — the
            // same place the crop editor names its source.
            Positioned(
              left: 16,
              top: 14,
              child: IgnorePointer(child: _BrushBadge(
                color: widget.selectedColor,
                size: widget.brushSize,
                isBinaryMode: widget.isBinaryMode,
                l10n: l10n,
              )),
            ),

            Positioned(
              right: 16,
              bottom: 14,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CanvasZoomPill(
                  percent: _controller.value.getMaxScaleOnAxis() * 100,
                  onZoomIn: () => _setScale(_controller.value.getMaxScaleOnAxis() * 1.25, viewport),
                  onZoomOut: () => _setScale(_controller.value.getMaxScaleOnAxis() / 1.25, viewport),
                  onFit: () => _controller.value = Matrix4.identity(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "White brush · 48 px", or the binary-mode notice that replaces it.
///
/// Replaces the full-width banner binary mode used to push the canvas down
/// with: the state belongs where the strokes land, and the toolbar's own
/// button already carries the accent that says the mode is on.
class _BrushBadge extends StatelessWidget {
  final Color color;
  final double size;
  final bool isBinaryMode;
  final AppLocalizations l10n;

  const _BrushBadge({
    required this.color,
    required this.size,
    required this.isBinaryMode,
    required this.l10n,
  });

  /// The name of the swatch this colour came from. The view is handed the
  /// brush with its opacity already applied, so the alpha is dropped before
  /// matching — otherwise every colour is an unnamed one.
  String? _colorName() {
    switch (color.toARGB32() & 0x00FFFFFF) {
      case 0xFFFFFF:
        return l10n.white;
      case 0x000000:
        return l10n.black;
      default:
        if (color.toARGB32() & 0x00FFFFFF == Colors.red.toARGB32() & 0x00FFFFFF) return l10n.red;
        if (color.toARGB32() & 0x00FFFFFF == Colors.green.toARGB32() & 0x00FFFFFF) return l10n.green;
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _colorName();

    return CanvasBadge(
      icon: isBinaryMode ? Icons.contrast : null,
      label: isBinaryMode
          ? l10n.binaryModeActive
          : name == null
              ? '${size.round()} px'
              : l10n.maskBrushBadge(name, size.round()),
    );
  }
}

/// Summary strip below the canvas: what a save writes, at what size, and
/// where it lands — the same numbers the save is about to use, stated before
/// the user commits. Mirrors the crop editor's output preview.
class _MaskOutputBar extends StatelessWidget {
  final ui.Image? image;
  final bool isBinaryMode;
  final AppLocalizations l10n;
  final ColorScheme colorScheme;

  const _MaskOutputBar({
    required this.image,
    required this.isBinaryMode,
    required this.l10n,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // The tracked caption the app names a group of controls with, which is
    // what `10o` draws here: 输出 is a heading over the line beside it, not a
    // field label sharing its weight.
    final labelStyle = textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      letterSpacing: AppType.trackedLabelSpacing,
    );

    final summary = image == null
        ? '—'
        : isBinaryMode
            ? l10n.maskOutputSummary(image!.width, image!.height)
            : l10n.maskCompositeOutputSummary(image!.width, image!.height);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        // The column tone and the panel-edge hairline, like the toolbar above
        // it and the console below. This was `surface` over a `surface` panel
        // — a bar with no edge of its own on a ground it matched.
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.surfaceContainerHigh)),
      ),
      child: Row(
        children: [
          Text(l10n.maskOutputLabel, style: labelStyle),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              summary,
              // Mono: this is dimensions and a format, and it sits directly
              // above a console of monospaced log lines.
              style: textTheme.bodySmall?.mono.copyWith(color: colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.accentTint,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.subdirectory_arrow_right, size: 12, color: colorScheme.onAccentTint),
                const SizedBox(width: 6),
                Text(
                  // The workspace, not a filename: the name a save picks
                  // carries a timestamp minted at save time, and printing a
                  // guess at it is how the crop bar's destination line was
                  // wrong three ways at once.
                  l10n.maskWillSaveTo(l10n.cropResizeTempWorkspaceLabel),
                  style: textTheme.labelSmall?.copyWith(color: colorScheme.onAccentTint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
