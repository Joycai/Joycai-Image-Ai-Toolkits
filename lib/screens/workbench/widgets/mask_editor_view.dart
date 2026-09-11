import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/drawing_canvas.dart';
import 'canvas_overlays.dart';

/// Space the picture keeps from the canvas' edges, and its corner radius
/// (`A4A6` spec: 画布 r10，居中，四周留 10).
const double _kCanvasPadding = AppSpace.s10;
const double _kCanvasImageRadius = AppRadius.control;

/// Where the corner badge sits inside the picture.
const double _kBadgeInset = 8;

/// The output card's width and its distance from the canvas corner.
const double _kOutputCardWidth = 300;
const double _kOutputCardInset = 20;

/// The mask editor's canvas (`A4A6 · 1e`, `1f`).
///
/// A content layer, not glass: the canvas has no ground of its own — the
/// aurora shows through around the picture — and the output card is an
/// opaque panel, because what it carries is numbers to be read.
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
      // A load that finishes after the source moved on is not this image.
      if (mounted && _lastPath == path) {
        setState(() {
          _imageInfo = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Cleared, not kept: a failed load must not go on showing — and
      // exporting against — the previous picture's dimensions.
      if (mounted && _lastPath == path) {
        setState(() {
          _imageInfo = null;
          _isLoading = false;
        });
      }
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

    if (sourceImage == null) {
      return _CanvasMessage(
        icon: Icons.brush_outlined,
        iconColor: colorScheme.outline,
        title: l10n.noImagesSelected,
        body: l10n.maskEmptyDesc,
        actionLabel: l10n.goToGallery,
        onAction: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_imageInfo == null) {
      final path = sourceImage.path;
      return _CanvasMessage(
        icon: Icons.broken_image_outlined,
        iconColor: colorScheme.error,
        title: l10n.imageLoadFailed,
        body: l10n.maskLoadFailedDesc,
        actionLabel: l10n.refresh,
        onAction: () => _loadImage(path),
      );
    }
    return _buildCanvas(sourceImage.path, l10n, colorScheme);
  }

  /// Where the picture is on screen right now: the fitted rect the layout
  /// gives it, carried through the viewer's pan and zoom.
  Rect _imageRectOnScreen(Size viewport) {
    final image = _imageInfo!;
    final availW = math.max(0.0, viewport.width - 2 * _kCanvasPadding);
    final availH = math.max(0.0, viewport.height - 2 * _kCanvasPadding);
    final aspect = image.width / image.height;
    var w = availW;
    var h = aspect > 0 ? w / aspect : 0.0;
    if (h > availH) {
      h = availH;
      w = h * aspect;
    }
    final fitted = Rect.fromLTWH((viewport.width - w) / 2, (viewport.height - h) / 2, w, h);
    return MatrixUtils.transformRect(_controller.value, fitted);
  }

  Widget _buildCanvas(String path, AppLocalizations l10n, ColorScheme colorScheme) {
    final isPhone = Responsive.isMobile(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);

        final zoomPill = AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CanvasZoomPill(
            percent: _controller.value.getMaxScaleOnAxis() * 100,
            onZoomIn: () => _setScale(_controller.value.getMaxScaleOnAxis() * 1.25, viewport),
            onZoomOut: () => _setScale(_controller.value.getMaxScaleOnAxis() / 1.25, viewport),
            onFit: () => _controller.value = Matrix4.identity(),
          ),
        );
        final outputCard = _MaskOutputCard(
          image: _imageInfo!,
          isBinaryMode: widget.isBinaryMode,
          fullWidth: isPhone,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                maxScale: 10.0,
                minScale: 0.1,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(_kCanvasPadding),
                    child: AspectRatio(
                      aspectRatio: _imageInfo!.width / _imageInfo!.height,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_kCanvasImageRadius),
                        // The boundary is inside the clip: the export is the
                        // picture and the strokes, never the canvas around
                        // them — and never the badge, which is drawn outside
                        // the viewer for that reason.
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
                                  // boundary is part of the subtree `toImage`
                                  // composites.
                                  //
                                  // Driven by the notifiers, never setState:
                                  // this is the part that changes at pointer
                                  // rate for the length of a stroke.
                                  child: RepaintBoundary(
                                    child: ListenableBuilder(
                                      listenable: _canvasRepaint,
                                      builder: (context, _) {
                                        final mouse = widget.mousePosition.value;
                                        return CustomPaint(
                                          painter: MaskPainter(paths: widget.paths),
                                          foregroundPainter: mouse != null
                                              ? _BrushRingPainter(position: mouse, diameter: widget.brushSize)
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

            // What the brush will lay down, at the picture's top-left. Placed
            // over the viewer rather than inside it so it neither scales with
            // the zoom nor lands in the export; clamped to the canvas when
            // the picture is zoomed past its edges. Rebuilds on pan and zoom
            // only — the pointer never reaches it.
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final visible = _imageRectOnScreen(viewport).intersect(Offset.zero & viewport);
                if (visible.width < 64 || visible.height < 32) {
                  return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
                }
                return Positioned(
                  left: visible.left + _kBadgeInset,
                  top: visible.top + _kBadgeInset,
                  child: IgnorePointer(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: visible.width - 2 * _kBadgeInset),
                      child: _BrushBadge(
                        color: widget.selectedColor,
                        size: widget.brushSize,
                        isBinaryMode: widget.isBinaryMode,
                        l10n: l10n,
                      ),
                    ),
                  ),
                );
              },
            ),

            // The output card bottom-right, the zoom pill bottom-left. A phone
            // lays the card across the bottom with the pill above it; a
            // canvas too narrow for both side by side stacks the pill over the
            // card on the right rather than letting them overlap.
            if (isPhone)
              Positioned(
                left: _kCanvasPadding,
                right: _kCanvasPadding,
                bottom: _kCanvasPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    zoomPill,
                    const SizedBox(height: AppSpace.s6),
                    outputCard,
                  ],
                ),
              )
            else
              Positioned(
                left: _kOutputCardInset,
                right: _kOutputCardInset,
                bottom: _kOutputCardInset,
                child: Wrap(
                  // Right-to-left with runs stacking upward: on one line the
                  // card is at the right and the pill at the left; wrapped,
                  // the card keeps the corner and the pill sits above it.
                  textDirection: TextDirection.rtl,
                  verticalDirection: VerticalDirection.up,
                  alignment: WrapAlignment.spaceBetween,
                  // `start`, not `end`: an upward wrap flips the cross axis,
                  // so start is the bottom — the pill sits on the card's
                  // baseline rather than at the top of its run.
                  crossAxisAlignment: WrapCrossAlignment.start,
                  runSpacing: AppSpace.s6,
                  children: [outputCard, zoomPill],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The brush's footprint under the pointer (`1e`): a 1.5px white ring with a
/// dark line outside it, so it reads on any picture and on the binary
/// canvas. No fill — the colour is named in the badge.
class _BrushRingPainter extends CustomPainter {
  _BrushRingPainter({required this.position, required this.diameter});

  final Offset position;
  final double diameter;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = diameter / 2;
    canvas.drawCircle(
      position,
      radius + 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      position,
      math.max(0.0, radius - 0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _BrushRingPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.diameter != diameter;
}

/// "White brush · 48 px", or the binary-mode notice that replaces it.
///
/// Replaces the full-width banner binary mode used to push the canvas down
/// with: the state belongs where the strokes land, and the toolbar's own
/// button already carries the lens that says the mode is on.
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

    return _ImageBadge(
      // Inverted in binary mode (`1f`): the dark plate would vanish into the
      // black canvas, so the notice takes the light plate and dark ink.
      inverted: isBinaryMode,
      label: isBinaryMode
          ? l10n.binaryModeActive
          : name == null
              ? '${size.round()} px'
              : l10n.maskBrushBadge(name, size.round()),
    );
  }
}

/// A corner label on the picture: mono 11 on the fixed image plate, r4.
/// Never themed — what sits under it is a photograph, not the app.
class _ImageBadge extends StatelessWidget {
  const _ImageBadge({required this.label, this.inverted = false});

  final String label;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: inverted ? AppOverlay.onImagePlate.withValues(alpha: 0.9) : AppOverlay.imagePlate,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Mono, because what this says is a measurement: a brush width
          // that changes under the slider should not reflow the label around
          // it every time a digit does.
          style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                fontWeight: FontWeight.w400,
                color: inverted ? AppOverlay.ink : AppOverlay.onImagePlate,
              ),
        ),
      ),
    );
  }
}

/// A canvas with nothing to draw on (`1f` right): the 28px glyph, a 12/600
/// line, and a text button that does something about it.
class _CanvasMessage extends StatelessWidget {
  const _CanvasMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;

  /// One quiet line under the title saying why, or what to do (`1f`).
  final String? body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = this.body;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: iconColor),
            const SizedBox(height: AppSpace.s6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
            ),
            if (body != null) ...[
              const SizedBox(height: 2),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpace.s10),
            AppButton(
              label: actionLabel,
              variant: AppButtonVariant.text,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

/// What a save writes, at what size, and where it lands (`1e` 「输出预览卡」)
/// — the same numbers the save is about to use, stated before the user
/// commits. Mirrors the crop editor's output preview.
class _MaskOutputCard extends StatelessWidget {
  final ui.Image image;
  final bool isBinaryMode;

  /// A phone lays the card across the bottom of the canvas.
  final bool fullWidth;

  const _MaskOutputCard({
    required this.image,
    required this.isBinaryMode,
    required this.fullWidth,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final summary = isBinaryMode
        ? l10n.maskOutputSummary(image.width, image.height)
        : l10n.maskCompositeOutputSummary(image.width, image.height);

    return Container(
      width: fullWidth ? double.infinity : _kOutputCardWidth,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: colorScheme.shadowOverlay,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The tracked group caption, in the deep ink.
          Text(
            l10n.maskOutputLabel.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onAccentTint,
              letterSpacing: AppType.trackedLabelSpacing,
            ),
          ),
          const SizedBox(height: AppSpace.s6),
          Text(
            summary,
            style: textTheme.bodySmall?.mono.copyWith(color: colorScheme.onSurface, height: 1.6),
          ),
          const SizedBox(height: AppSpace.s6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: AppSpace.s6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Text(
              // The workspace, not a filename: the name a save picks carries a
              // timestamp minted at save time, and printing a guess at it is
              // how the crop bar's destination line was wrong three ways at
              // once.
              l10n.maskWillSaveTo(l10n.cropResizeTempWorkspaceLabel),
              style: textTheme.labelSmall?.mono.copyWith(
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
