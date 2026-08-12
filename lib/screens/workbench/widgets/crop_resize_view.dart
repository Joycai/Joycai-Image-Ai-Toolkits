import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/image_processing_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';
import 'canvas_overlays.dart';

const Map<String, String> _kSamplingLabels = {
  'lanczos': 'Lanczos',
  'cubic': 'Cubic',
  'linear': 'Linear',
  'nearest': 'Nearest',
};

class CropResizeView extends StatefulWidget {
  const CropResizeView({super.key});

  @override
  State<CropResizeView> createState() => _CropResizeViewState();
}

class _CropResizeViewState extends State<CropResizeView> {
  /// Crop rect in the editor's own local (Stack) coordinate space — used to
  /// position the floating badge over the live selection.
  Rect? _screenCropRect;

  /// The same crop rect in source-image pixel space — used for the numbers
  /// the badge and output strip actually print, so they always agree with
  /// what a save would produce.
  Rect? _pixelCropRect;

  double _zoomPercent = 100;

  ImageMetadata? _meta;
  String? _metaPath;
  /// The name "save a copy" would actually write, resolved rather than
  /// guessed.
  ///
  /// This strip used to build the name itself, and got it wrong three ways at
  /// once — it printed `crop_photo.jpg` where the save produced
  /// `<temp>/joycai/processed/crop_photo_1754899200000.png`. It now asks the
  /// same resolver the save calls, so the strip and the overwrite dialog and
  /// the file on disk cannot disagree.
  String? _copyFileName;

  /// Wraps the editor so the zoom pill can find its render box and simulate
  /// a mouse-wheel event at its center — extended_image's editor doesn't
  /// expose a public "set scale" call, only the gesture path a real wheel
  /// takes, so the +/- buttons replay that same path instead of a click.
  final GlobalKey _canvasKey = GlobalKey();

  void _loadMeta(String path) {
    if (_metaPath == path) return;
    _metaPath = path;
    ImageMetadataService().getMetadata(path).then((meta) {
      if (mounted && _metaPath == path) setState(() => _meta = meta);
    });
    // Rides on the same path-changed guard as the metadata: the copy's name is
    // derived from this path and has to be re-resolved whenever it changes.
    ImageProcessingService().resolveCropCopyTarget(path).then((target) {
      if (mounted && _metaPath == path) setState(() => _copyFileName = target.fileName);
    });
  }

  /// Reads the selection straight off the editor once it has laid out.
  ///
  /// [_handleEditChanged] only fires on an actual edit, so until the user drags
  /// something there is no crop rect anywhere — which left the size fields
  /// empty and the output strip reading `768×512 → –` about a picture whose
  /// output size was fully determined. The initial rect is a fact the editor
  /// already has; it just never announces it.
  void _publishInitialCropRect() {
    if (_pixelCropRect != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pixelCropRect != null) return;
      final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
      final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
      final rect = state?.getCropRect();
      if (rect == null) return;
      setState(() => _pixelCropRect = rect);
      uiState.setCropPixelSize(Size(rect.width, rect.height));
    });
  }

  void _handleEditChanged(EditActionDetails? details) {
    if (details == null || !mounted) return;
    final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
    final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
    final pixelRect = state?.getCropRect();
    final destRect = details.screenDestinationRect;

    double? zoomPercent;
    if (destRect != null && _meta != null && _meta!.width > 0) {
      zoomPercent = destRect.width / _meta!.width * 100;
    }

    setState(() {
      _screenCropRect = details.screenCropRect;
      _pixelCropRect = pixelRect;
      if (zoomPercent != null) _zoomPercent = zoomPercent;
    });

    // Published rather than kept: the toolbar's width/height fields stand at
    // these numbers until the user types over them, and this callback is the
    // only place they arrive.
    uiState.setCropPixelSize(
      pixelRect == null ? null : Size(pixelRect.width, pixelRect.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiState = Provider.of<WorkbenchUIState>(context);
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final sourceImage = uiState.cropResizeSourceImage;

    if (sourceImage == null) {
      // The output strip stays even with nothing loaded: it is the screen's
      // chrome, not a result panel, and a bar that appears only once an image
      // arrives makes the whole layout jump under the user.
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.crop, size: 64, color: colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(l10n.noImagesSelected),
                  const SizedBox(height: 16),
                  AppButton(
                    label: l10n.goToGallery,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
                  ),
                ],
              ),
            ),
          ),
          _OutputPreviewBar(
            meta: null,
            pixelCropRect: null,
            targetWidth: null,
            targetHeight: null,
            samplingMethod: uiState.samplingMethod,
            copyFileName: null,
            l10n: l10n,
            colorScheme: colorScheme,
          ),
        ],
      );
    }

    _loadMeta(sourceImage.path);
    _publishInitialCropRect();

    return Column(
      children: [
        Expanded(
          child: Container(
            // The same neutral the mask editor and the comparator stand their
            // pictures on, and what the spec draws (#e9edec). It was black87
            // here — the one canvas of the three that went dark, which made
            // moving between the workbench tools read as changing app.
            color: colorScheme.surfaceContainerHigh,
            child: Stack(
              children: [
                Positioned.fill(
                  child: KeyedSubtree(
                    key: _canvasKey,
                    child: ExtendedImage.file(
                      File(sourceImage.path),
                      key: ValueKey("${sourceImage.path}_${uiState.cropAspectRatio}"),
                      fit: BoxFit.contain,
                      mode: ExtendedImageMode.editor,
                      enableLoadState: true,
                      extendedImageEditorKey: uiState.cropKey,
                      initEditorConfigHandler: (state) {
                        return EditorConfig(
                          maxScale: 8.0,
                          cropRectPadding: const EdgeInsets.all(20.0),
                          hitTestSize: 20.0,
                          cropAspectRatio: uiState.cropAspectRatio,
                          cropLayerPainter: const _EightHandleCropLayerPainter(),
                          editorMaskColorHandler: _maskColor,
                          editActionDetailsIsChanged: _handleEditChanged,
                        );
                      },
                    ),
                  ),
                ),
                // Names what is under the crop overlay, and — the reason it
                // says *preview* — marks the canvas as the untouched source
                // rather than a render of the pending output. The file's
                // native size lives in the toolbar caption instead.
                Positioned(
                  left: 16,
                  top: 14,
                  child: CanvasBadge(label: l10n.cropResizeCanvasLabel(sourceImage.name)),
                ),
                if (_screenCropRect != null && _pixelCropRect != null)
                  _CropBadge(screenRect: _screenCropRect!, pixelRect: _pixelCropRect!),
                Positioned(
                  right: 16,
                  bottom: 14,
                  child: CanvasZoomPill(
                    percent: _zoomPercent,
                    onZoomIn: () => _nudgeZoom(1),
                    onZoomOut: () => _nudgeZoom(-1),
                    onFit: () => _fitToWindow(uiState),
                  ),
                ),
              ],
            ),
          ),
        ),
        _OutputPreviewBar(
          meta: _meta,
          pixelCropRect: _pixelCropRect,
          targetWidth: uiState.targetWidth,
          targetHeight: uiState.targetHeight,
          samplingMethod: uiState.samplingMethod,
          copyFileName: _copyFileName,
          l10n: l10n,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  /// What the area outside the selection is dimmed with.
  ///
  /// The package's default is `scaffoldBackgroundColor` at 80% — which on the
  /// light theme washes the discarded part of the picture out to near-white
  /// over a black canvas, and at that strength hides the very thing the user
  /// is framing against. Black, so it carries no theme hue onto a photograph
  /// (the same reasoning as [ImageCard]'s overlay ink), and a notch weaker so
  /// the surroundings stay legible while the crop is being placed.
  Color _maskColor(BuildContext context, bool pointerDown) =>
      Colors.black.withValues(alpha: pointerDown ? 0.35 : 0.55);

  void _fitToWindow(WorkbenchUIState uiState) {
    final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
    state?.reset();
  }

  /// extended_image's editor exposes zoom only through gestures (touch
  /// pinch, mouse wheel), not a public "set scale" call. Rather than a dead
  /// button, this replays one mouse-wheel notch at the canvas' center —
  /// the same [PointerScrollEvent] path `_handlePointerSignal` already
  /// listens for — so +/- drive the exact mechanism scrolling does.
  void _nudgeZoom(int direction) {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final center = renderObject.localToGlobal(renderObject.size.center(Offset.zero));
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        position: center,
        kind: PointerDeviceKind.mouse,
        scrollDelta: Offset(0, direction * 120),
      ),
    );
  }
}

/// Draws the package's default 4 corner marks plus 4 edge-midpoint handles,
/// so the crop rect reads as fully grabbable along every edge, not just at
/// its corners — and keeps the rule-of-thirds grid up at all times.
class _EightHandleCropLayerPainter extends EditorCropLayerPainter {
  const _EightHandleCropLayerPainter();

  /// The package draws the thirds only while `pointerDown`, so the guides
  /// appear during a drag and vanish the moment they could be used to judge
  /// the result. Composition is decided when the pointer is *up*; this keeps
  /// the grid standing, at a third of the border's weight so it guides
  /// without becoming part of the picture.
  @override
  void paintLines(
    Canvas canvas,
    Size size,
    ExtendedImageCropLayerPainter painter,
  ) {
    super.paintLines(canvas, size, painter);
    if (painter.pointerDown) return; // super already drew them

    final Rect rect = painter.cropRect;
    final Paint paint = Paint()
      ..color = painter.lineColor.withValues(alpha: 0.35)
      ..strokeWidth = painter.lineHeight
      ..style = PaintingStyle.stroke;

    for (var i = 1; i <= 2; i++) {
      final double x = rect.left + rect.width / 3 * i;
      final double y = rect.top + rect.height / 3 * i;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  @override
  void paintCorners(
    Canvas canvas,
    Size size,
    ExtendedImageCropLayerPainter painter,
  ) {
    super.paintCorners(canvas, size, painter);

    final Rect cropRect = painter.cropRect;
    final Paint paint = Paint()
      ..color = painter.cornerColor
      ..style = PaintingStyle.fill;

    const double handleLength = 14.0;
    const double handleThickness = 3.0;
    final double midX = cropRect.left + cropRect.width / 2;
    final double midY = cropRect.top + cropRect.height / 2;

    void horizontal(double cx, double cy) => canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: handleLength, height: handleThickness),
          paint,
        );
    void vertical(double cx, double cy) => canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: handleThickness, height: handleLength),
          paint,
        );

    horizontal(midX, cropRect.top);
    horizontal(midX, cropRect.bottom);
    vertical(cropRect.left, midY);
    vertical(cropRect.right, midY);
  }
}

/// Floating "{w}×{h} · {ratio}" readout anchored to the live crop rect's
/// top-left, so the numbers a save will actually use are visible while
/// dragging rather than only after releasing.
class _CropBadge extends StatelessWidget {
  final Rect screenRect;
  final Rect pixelRect;

  const _CropBadge({required this.screenRect, required this.pixelRect});

  @override
  Widget build(BuildContext context) {
    final w = pixelRect.width.round();
    final h = pixelRect.height.round();
    final ratio = _simplifiedRatio(w, h);

    return Positioned(
      left: screenRect.left.clamp(0, double.infinity),
      top: (screenRect.top - 30).clamp(0, double.infinity),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            ratio == null ? '$w × $h' : '$w × $h · $ratio',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  String? _simplifiedRatio(int w, int h) {
    if (w <= 0 || h <= 0) return null;
    final g = _gcd(w, h);
    if (g == 0) return null;
    return '${w ~/ g}:${h ~/ g}';
  }

  int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);
}

/// Summary strip below the canvas: original size -> output size, whether
/// scaling is happening on top of the crop, which sampler will run, and
/// where the copy will land — the same numbers a save is about to use, shown
/// before the user commits.
class _OutputPreviewBar extends StatelessWidget {
  final ImageMetadata? meta;
  final Rect? pixelCropRect;
  final int? targetWidth;
  final int? targetHeight;
  final String samplingMethod;
  /// Resolved by the parent from ImageProcessingService, never derived here.
  final String? copyFileName;
  final AppLocalizations l10n;
  final ColorScheme colorScheme;

  const _OutputPreviewBar({
    required this.meta,
    required this.pixelCropRect,
    required this.targetWidth,
    required this.targetHeight,
    required this.samplingMethod,
    required this.copyFileName,
    required this.l10n,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final cropW = pixelCropRect?.width.round();
    final cropH = pixelCropRect?.height.round();
    final outW = targetWidth ?? cropW;
    final outH = targetHeight ?? cropH;

    final originalSize = meta != null ? '${meta!.width}×${meta!.height}' : '–';
    final outputSize = (outW != null && outH != null) ? '$outW×$outH' : '–';

    final isScaling = cropW != null && cropW > 0 && outW != null && outW != cropW;
    final percent = isScaling ? (outW / cropW * 100).round() : 100;
    final operation = isScaling ? l10n.cropResizeCropAndScale(percent) : l10n.cropResizeCropOnly;
    final samplingLabel = _kSamplingLabels[samplingMethod] ?? samplingMethod;

    final destination = copyFileName == null
        ? null
        : '${l10n.cropResizeTempWorkspaceLabel} / $copyFileName';

    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    return Container(
      // 40 and an accent capsule for the destination, the same strip the mask
      // editor draws below its canvas — the spec gives both tools one bar.
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withAlpha(80))),
      ),
      child: Row(
        children: [
          Text(l10n.cropResizeOutputPreview, style: labelStyle),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.cropResizeOutputSummary(originalSize, outputSize, operation, samplingLabel),
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (destination != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Container(
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
                    Flexible(
                      child: Text(
                        l10n.cropResizeWillSaveTo(destination),
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.onAccentTint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

}
