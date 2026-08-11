import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_paths.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/image_metadata_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import '../../../widgets/app_button.dart';

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
  String? _tempWorkspaceDir;

  /// Wraps the editor so the zoom pill can find its render box and simulate
  /// a mouse-wheel event at its center — extended_image's editor doesn't
  /// expose a public "set scale" call, only the gesture path a real wheel
  /// takes, so the +/- buttons replay that same path instead of a click.
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    AppPaths.getTempDirectory().then((dir) {
      if (mounted) setState(() => _tempWorkspaceDir = dir);
    });
  }

  void _loadMeta(String path) {
    if (_metaPath == path) return;
    _metaPath = path;
    ImageMetadataService().getMetadata(path).then((meta) {
      if (mounted && _metaPath == path) setState(() => _meta = meta);
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
            tempWorkspaceDir: null,
            sourceName: null,
            l10n: l10n,
            colorScheme: colorScheme,
          ),
        ],
      );
    }

    _loadMeta(sourceImage.path);

    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black87,
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
                          editActionDetailsIsChanged: _handleEditChanged,
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  top: 14,
                  right: 16,
                  child: _CanvasLabel(name: sourceImage.name, l10n: l10n),
                ),
                if (_screenCropRect != null && _pixelCropRect != null)
                  _CropBadge(screenRect: _screenCropRect!, pixelRect: _pixelCropRect!),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _ZoomPill(
                    percent: _zoomPercent,
                    onZoomIn: () => _nudgeZoom(1),
                    onZoomOut: () => _nudgeZoom(-1),
                    onFit: () => _fitToWindow(uiState),
                    l10n: l10n,
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
          tempWorkspaceDir: _tempWorkspaceDir,
          sourceName: sourceImage.name,
          l10n: l10n,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

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
/// its corners.
class _EightHandleCropLayerPainter extends EditorCropLayerPainter {
  const _EightHandleCropLayerPainter();

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

/// "{name}（original preview）" over the canvas' top-left.
///
/// Names what is under the crop overlay, and — the reason it says *preview* —
/// marks the canvas as the untouched source rather than a render of the
/// pending output. The file's native size lives in the toolbar caption
/// instead; repeating it here would be two answers to one question.
class _CanvasLabel extends StatelessWidget {
  final String name;
  final AppLocalizations l10n;

  const _CanvasLabel({required this.name, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        l10n.cropResizeCanvasLabel(name),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white.withValues(alpha: 0.7),
          fontFamily: 'monospace',
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Bottom-right floating readout: current zoom against the source image's
/// native resolution (100% = one screen pixel per source pixel), plus a fit
/// action. The +/- steps mirror the package's own mouse-wheel zoom rather
/// than driving a scale setter the package doesn't expose publicly.
class _ZoomPill extends StatelessWidget {
  final double percent;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final AppLocalizations l10n;

  const _ZoomPill({
    required this.percent,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pillIcon(Icons.remove, onZoomOut),
          SizedBox(
            width: 44,
            child: Text(
              '${percent.round()}%',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          _pillIcon(Icons.add, onZoomIn),
          Container(width: 1, height: 14, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 4)),
          InkWell(
            onTap: onFit,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(l10n.fitToWindow, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillIcon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
    );
  }
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
  final String? tempWorkspaceDir;
  final String? sourceName;
  final AppLocalizations l10n;
  final ColorScheme colorScheme;

  const _OutputPreviewBar({
    required this.meta,
    required this.pixelCropRect,
    required this.targetWidth,
    required this.targetHeight,
    required this.samplingMethod,
    required this.tempWorkspaceDir,
    required this.sourceName,
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

    final name = sourceName;
    final destination = (name == null || tempWorkspaceDir == null)
        ? null
        : '${l10n.cropResizeTempWorkspaceLabel} / crop_${_baseName(name)}${_extension(name)}';

    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    return Container(
      height: 34,
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
            Icon(Icons.subdirectory_arrow_right, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.cropResizeWillSaveTo(destination),
                style: labelStyle,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }
}
