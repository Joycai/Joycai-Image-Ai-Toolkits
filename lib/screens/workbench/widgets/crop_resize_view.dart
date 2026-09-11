import 'dart:io';
import 'dart:ui' show ClipOp;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
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

/// `A4 · 1a`: the picture stands centred with 10 around it.
const double _kCanvasMargin = AppSpace.s10;

/// The output preview card's inset from the canvas corner (`1a`), and its
/// width.
const double _kCardInset = 20;
const double _kCardWidth = 300;

/// The phone's full-width card (`1b`) sits this far in from the edges.
const double _kPhoneCardInset = 14;

/// The crop tool's canvas (`A4 · 1a`).
///
/// A content layer, not glass: the picture on the window's own ground, the
/// crop box drawn straight onto it, and one opaque floating piece — the
/// output preview card, bottom-right — because what it holds are numbers to
/// read before committing, not controls.
class CropResizeView extends StatefulWidget {
  const CropResizeView({super.key});

  @override
  State<CropResizeView> createState() => _CropResizeViewState();
}

class _CropResizeViewState extends State<CropResizeView> {
  /// The crop selection in the editor's own local (Stack) coordinate space,
  /// for anchoring the size readout over it.
  ///
  /// [EditActionDetails.cropRect], not its `screenCropRect`. The two differ by
  /// `layoutTopLeft`, which in this arrangement is 117px of chrome the
  /// readout's Stack does not share — so the readout sat that far below the
  /// selection it was labelling. It went unnoticed because it only ever
  /// appeared while dragging, when the eye is on the handle rather than the
  /// readout.
  Rect? _layerCropRect;

  /// Where the picture itself lies, in the same space as [_layerCropRect].
  ///
  /// The crop layer paints over the editor's whole box, which is wider or
  /// taller than the picture. `1a` darkens only the picture outside the
  /// selection, and the source badge sits on the picture's corner, not the
  /// box's — both need this rect.
  Rect? _layerImageRect;

  /// The same crop rect in source-image pixel space — used for the numbers
  /// the readout and the output card actually print, so they always agree
  /// with what a save would produce.
  Rect? _pixelCropRect;

  double _zoomPercent = 100;

  ImageMetadata? _meta;
  String? _metaPath;

  /// The name "save a copy" would actually write, resolved rather than
  /// guessed.
  ///
  /// This readout used to build the name itself, and got it wrong three ways
  /// at once — it printed `crop_photo.jpg` where the save produced
  /// `<temp>/joycai/processed/crop_photo_1754899200000.png`. It now asks the
  /// same resolver the save calls, so the card and the overwrite dialog and
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

  /// [EditActionDetails.layerDestinationRect], guarded: the getter
  /// dereferences the layout rect, which is null until the editor has laid
  /// out once.
  static Rect? _imageRectOf(EditActionDetails? details) =>
      details?.layoutRect == null ? null : details!.layerDestinationRect;

  /// Reads the selection straight off the editor once it has laid out.
  ///
  /// [_handleEditChanged] only fires on an actual edit, so until the user drags
  /// something there is no crop rect anywhere — which left the size fields
  /// empty and the output card reading `768×512 → –` about a picture whose
  /// output size was fully determined. The initial rect is a fact the editor
  /// already has; it just never announces it.
  ///
  /// Both rects, not only the pixel one: the readout is drawn from the layer
  /// rect, so publishing only the pixel rect fixed the toolbar and the output
  /// card while leaving the readout invisible until the first drag.
  void _publishInitialCropRect() {
    if (_pixelCropRect != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pixelCropRect != null) return;
      final uiState = Provider.of<WorkbenchUIState>(context, listen: false);
      final state = uiState.cropKey.currentState as ExtendedImageEditorState?;
      final rect = state?.getCropRect();
      if (rect == null) return;
      setState(() {
        _pixelCropRect = rect;
        _layerCropRect = state?.editAction?.cropRect ?? _layerCropRect;
        _layerImageRect = _imageRectOf(state?.editAction) ?? _layerImageRect;
      });
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
      _layerCropRect = details.cropRect;
      _layerImageRect = _imageRectOf(details) ?? _layerImageRect;
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
    final sourceImage = uiState.cropResizeSourceImage;

    if (sourceImage == null) return _buildEmpty(context, l10n);

    _loadMeta(sourceImage.path);
    _publishInitialCropRect();

    final phone = Responsive.isMobile(context);
    final imageRect = _layerImageRect;

    final card = _OutputPreviewCard(
      meta: _meta,
      pixelCropRect: _pixelCropRect,
      targetWidth: uiState.targetWidth,
      targetHeight: uiState.targetHeight,
      samplingMethod: uiState.samplingMethod,
      copyFileName: _copyFileName,
    );

    final zoomPill = CanvasZoomPill(
      percent: _zoomPercent,
      onZoomIn: () => _nudgeZoom(1),
      onZoomOut: () => _nudgeZoom(-1),
      onFit: () => _fitToWindow(uiState),
    );

    return Stack(
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
                  cropRectPadding: const EdgeInsets.all(_kCanvasMargin),
                  hitTestSize: 20.0,
                  cropAspectRatio: uiState.cropAspectRatio,
                  lineColor: Colors.white.withValues(alpha: 0.9),
                  lineHeight: 1,
                  cornerColor: Colors.white,
                  // A new painter only when the picture's rect moves: the
                  // crop layer repaints on a painter that compares unequal,
                  // and on nothing else this rect affects.
                  cropLayerPainter: _CropLayerPainter(imageRect: imageRect),
                  editorMaskColorHandler: _maskColor,
                  editActionDetailsIsChanged: _handleEditChanged,
                );
              },
            ),
          ),
        ),
        // Names what is under the crop box, and — the reason it says
        // *preview* — marks the canvas as the untouched source rather than a
        // render of the pending output. On the picture's own corner.
        Positioned(
          left: (imageRect?.left ?? _kCanvasMargin) + CanvasBadge.inset,
          top: (imageRect?.top ?? _kCanvasMargin) + CanvasBadge.inset,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: imageRect == null ? 360 : (imageRect.width - CanvasBadge.inset * 2).clamp(0, 360),
            ),
            child: CanvasBadge(label: l10n.cropResizeCanvasLabel(sourceImage.name)),
          ),
        ),
        if (_layerCropRect != null && _pixelCropRect != null)
          _CropReadout(cropRect: _layerCropRect!, pixelRect: _pixelCropRect!),
        if (phone) ...[
          Positioned(top: _kCanvasMargin, right: _kCanvasMargin, child: zoomPill),
          Positioned(left: _kPhoneCardInset, right: _kPhoneCardInset, bottom: _kPhoneCardInset, child: card),
        ] else ...[
          Positioned(left: _kCardInset, bottom: _kCardInset, child: zoomPill),
          Positioned(right: _kCardInset, bottom: _kCardInset, width: _kCardWidth, child: card),
        ],
      ],
    );
  }

  /// `1b` right: a 28px glyph in the outline colour, a 12/600 title, and the
  /// way back to the gallery as a deep-ink text button.
  Widget _buildEmpty(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.crop, size: 28, color: scheme.outline),
          const SizedBox(height: AppSpace.s6),
          Text(
            l10n.noImagesSelected,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.cropEmptyDesc,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.s4),
          AppButton(
            label: l10n.goToGallery,
            variant: AppButtonVariant.text,
            onPressed: () => Provider.of<AppState>(context, listen: false).setWorkbenchTab(0),
          ),
        ],
      ),
    );
  }

  /// What the picture outside the selection is darkened with: the image
  /// plate's warm near-black at 55% (`1a`), easing to 35% while a handle is
  /// held so the surroundings stay legible as the crop is placed.
  ///
  /// Never a theme colour: this lies over a photograph.
  Color _maskColor(BuildContext context, bool pointerDown) =>
      AppOverlay.imagePlate.withValues(alpha: pointerDown ? 0.35 : 0.55);

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

/// `1a`'s crop box: the picture outside the selection darkened (only the
/// picture — its rounded rect, not the editor's whole box), a 1px white edge
/// at 90%, the rule of thirds at 35% standing at all times, and eight white
/// handles — 8×8 at the corners, 12×3 and 3×12 on the edges — each with a
/// small shadow so it holds on a light photograph.
class _CropLayerPainter extends EditorCropLayerPainter {
  const _CropLayerPainter({required this.imageRect});

  /// The picture in layer space; null until the editor has laid out, when
  /// the whole box is darkened instead.
  final Rect? imageRect;

  static const double _cornerHandle = 8;
  static const double _edgeLength = 12;
  static const double _edgeThickness = 3;

  @override
  void paintMask(Canvas canvas, Rect rect, ExtendedImageCropLayerPainter painter) {
    final area = imageRect ?? rect;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(area, const Radius.circular(AppRadius.control)));
    canvas.clipRect(painter.cropRect, clipOp: ClipOp.difference);
    canvas.drawRect(area, Paint()..color = painter.maskColor);
    canvas.restore();
  }

  /// The package draws the thirds only while `pointerDown`, so the guides
  /// appeared during a drag and vanished the moment they could be used to
  /// judge the result. Composition is decided when the pointer is *up*.
  @override
  void paintLines(Canvas canvas, Size size, ExtendedImageCropLayerPainter painter) {
    final Rect rect = painter.cropRect;

    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = painter.lineColor
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    final Paint thirds = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 1; i <= 2; i++) {
      final double x = rect.left + rect.width / 3 * i;
      final double y = rect.top + rect.height / 3 * i;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), thirds);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), thirds);
    }
  }

  @override
  void paintCorners(Canvas canvas, Size size, ExtendedImageCropLayerPainter painter) {
    final Rect r = painter.cropRect;
    final Paint fill = Paint()..color = painter.cornerColor;
    final Paint shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

    void handle(Offset center, double width, double height) {
      final rect = Rect.fromCenter(center: center, width: width, height: height);
      canvas.drawRect(rect.shift(const Offset(0, 1)), shadow);
      canvas.drawRect(rect, fill);
    }

    for (final corner in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      handle(corner, _cornerHandle, _cornerHandle);
    }
    handle(r.topCenter, _edgeLength, _edgeThickness);
    handle(r.bottomCenter, _edgeLength, _edgeThickness);
    handle(r.centerLeft, _edgeThickness, _edgeLength);
    handle(r.centerRight, _edgeThickness, _edgeLength);
  }

  @override
  bool operator ==(Object other) => other is _CropLayerPainter && other.imageRect == imageRect;

  @override
  int get hashCode => imageRect.hashCode;
}

/// `1a`'s readout inside the crop box, centred along its top edge 8 down:
/// "{w} × {h} · {ratio}", the numbers a save will actually use, on screen from
/// the moment the tool opens rather than only while dragging.
///
/// Inside the box, not above it: above, a selection near the top of the
/// canvas pushes the readout off the edge, and clamping it back lands it
/// somewhere that no longer points at anything.
class _CropReadout extends StatelessWidget {
  final Rect cropRect;
  final Rect pixelRect;

  const _CropReadout({required this.cropRect, required this.pixelRect});

  @override
  Widget build(BuildContext context) {
    final w = pixelRect.width.round();
    final h = pixelRect.height.round();
    final ratio = _simplifiedRatio(w, h);

    return Positioned(
      left: cropRect.left,
      top: cropRect.top + CanvasBadge.inset,
      width: cropRect.width,
      child: Center(
        child: CanvasBadge(label: ratio == null ? '$w × $h' : '$w × $h · $ratio'),
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

/// `1a`'s output preview card: what a save produces — original size → output
/// size, whether it scales on top of the crop, which sampler runs — and where
/// the copy lands, stated before the user commits.
///
/// An opaque panel over the canvas (surface ground, hairline, r16, a soft
/// 14% shadow), not glass: these are numbers to read.
class _OutputPreviewCard extends StatelessWidget {
  final ImageMetadata? meta;
  final Rect? pixelCropRect;
  final int? targetWidth;
  final int? targetHeight;
  final String samplingMethod;

  /// Resolved by the parent from ImageProcessingService, never derived here.
  final String? copyFileName;

  const _OutputPreviewCard({
    required this.meta,
    required this.pixelCropRect,
    required this.targetWidth,
    required this.targetHeight,
    required this.samplingMethod,
    required this.copyFileName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.14),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The tracked group caption, in the deep ink.
          Text(
            l10n.cropResizeOutputPreview.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall!.copyWith(
              color: scheme.onAccentTint,
              letterSpacing: AppType.trackedLabelSpacing,
            ),
          ),
          const SizedBox(height: AppSpace.s6),
          Text(
            l10n.cropResizeOutputSummary(originalSize, outputSize, operation, samplingLabel),
            // Two dimensions, a percentage and an algorithm name — a line of
            // measurements, and the one the user reads to check the save
            // before making it.
            style: textTheme.bodySmall!.mono.copyWith(
              color: scheme.onSurface,
              height: AppType.looseHeight,
            ),
          ),
          if (destination != null) ...[
            const SizedBox(height: AppSpace.s6),
            Container(
              padding: const EdgeInsets.only(top: AppSpace.s6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Text(
                l10n.cropResizeWillSaveTo(destination),
                style: textTheme.labelSmall!.mono.copyWith(
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
