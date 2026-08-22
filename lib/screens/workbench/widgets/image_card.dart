import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/design_tokens.dart';
import '../../../core/responsive.dart';
import '../../../core/thumbnail_decode.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_image.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/video_thumbnail_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import 'image_card_context_menu.dart';

/// Ink laid over a photograph, for the chips that have to stay readable on
/// top of one.
///
/// Deliberately not from the [ColorScheme]: these sit on user pictures, not
/// on the app's own surfaces, and a chip tinted to the theme is illegible the
/// moment someone loads an image in that hue. Black and white carry no hue of
/// their own, so they stay neutral under the app's grey scale too.
///
/// [_chipScrim] and [_barScrim] are heavier than the values they replace,
/// because there is no blur under them any more. The dimensions badge and the
/// hover bar were both frosted — a [BackdropFilter] each — and the badge shows
/// on every card that has finished reading its metadata, so a screen of
/// thumbnails meant dozens of `saveLayer`-plus-blur passes per frame and the
/// raster thread never finished one. Opacity alone separates a chip from the
/// picture just as well at this size; the blur was only ever holding contrast
/// that these values now hold directly.
const Color _overlayScrim = Color(0x52000000);
const Color _overlayScrimStrong = Color(0x73000000);
const Color _chipScrim = Color(0x99000000);
const Color _barScrim = Color(0xBF000000);
const Color _overlayInk = Color(0xEBFFFFFF);

/// A single thumbnail tile in the gallery grid. Handles its own thumbnail
/// loading and hover/selection chrome; all file actions are delegated to
/// [showImageCardContextMenu].
class ImageCard extends StatefulWidget {
  final AppImage imageFile;

  /// This picture's place in the selection, counting from 1; `0` when it is
  /// not selected.
  ///
  /// A number rather than a flag because the order is the order the pictures
  /// reach the model, and the reference strip in the config panel labels them
  /// the same way — a prompt that refers to "the second image" needs the two
  /// to agree.
  final int selectionNumber;

  final double thumbnailSize;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const ImageCard({
    super.key,
    required this.imageFile,
    required this.selectionNumber,
    required this.thumbnailSize,
    required this.onTap,
    this.onDoubleTap,
  });

  bool get isSelected => selectionNumber > 0;

  @override
  State<ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<ImageCard> {
  String _dimensions = "";
  bool _isHovering = false;
  String? _videoThumbnailPath;

  @override
  void initState() {
    super.initState();
    // Seed from the cache first: a tile scrolled back into view already has its
    // measurement, and going through the async path for it would cost a
    // scheduled task and a second build to show a value that was in hand.
    _dimensions = ImageMetadataService().peek(widget.imageFile.path)?.displayString ?? "";
    if (_dimensions.isEmpty) _getImageDimensions();
    _loadVideoThumbnail();
  }

  @override
  void didUpdateWidget(covariant ImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile.path != widget.imageFile.path) {
      // Same cache-first rule as initState — a recycled tile usually lands on a
      // file the grid has already measured.
      final known = ImageMetadataService().peek(widget.imageFile.path);
      setState(() {
        _dimensions = known?.displayString ?? "";
        _videoThumbnailPath = null;
      });
      if (known == null) _getImageDimensions();
      _loadVideoThumbnail();
    }
  }

  Future<void> _getImageDimensions() async {
    final metadata = await ImageMetadataService().getMetadata(widget.imageFile.path);
    if (metadata != null && mounted) {
      setState(() {
        _dimensions = metadata.displayString;
      });
    }
  }

  Future<void> _loadVideoThumbnail() async {
    if (!AppConstants.isVideoFile(widget.imageFile.path)) return;

    final path = widget.imageFile.path;
    final cachePath = await VideoThumbnailService.instance.getThumbnail(path);
    // Widget may have been recycled to a different file while awaiting.
    if (cachePath != null && mounted && widget.imageFile.path == path) {
      setState(() {
        _videoThumbnailPath = cachePath;
      });
    }
  }

  Widget _buildThumbnail(BuildContext context, ColorScheme colorScheme, {double? width, double? height}) {
    final isVideo = AppConstants.isVideoFile(widget.imageFile.path);

    if (isVideo) {
      return Container(
        width: width,
        height: height,
        color: colorScheme.surfaceContainerHighest,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_videoThumbnailPath != null)
              Positioned.fill(
                child: Image.file(
                  File(_videoThumbnailPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            Container(
              color: _videoThumbnailPath != null ? _overlayScrim : Colors.transparent,
            ),
            const Icon(
              Icons.play_circle_filled_rounded,
              size: 40,
              color: _overlayInk,
            ),
            Positioned(
              bottom: 4,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _overlayScrimStrong,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, size: 10, color: _overlayInk),
                    SizedBox(width: 2),
                    // Left off the type scale on purpose: its smallest slot is
                    // labelSmall at 10, and +25% does not fit this badge.
                    Text(
                      "VIDEO",
                      style: TextStyle(color: _overlayInk, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Image(
      image: ResizeImage(
        widget.imageFile.imageProvider,
        // Snapped to a ladder rather than taken at the exact painted size —
        // see [thumbnailDecodeWidth]. The size slider is a drag, and a decode
        // width that follows it pixel for pixel re-decodes the whole visible
        // grid on every frame of that drag.
        width: thumbnailDecodeWidth(context, width ?? widget.thumbnailSize),
      ),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Container(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(Icons.broken_image, color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = Responsive.isMobile(context);

    return Draggable<AppImage>(
      data: widget.imageFile,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 100,
          height: 100,
          child: _buildThumbnail(context, colorScheme, width: 100, height: 100),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCardContent(context, colorScheme, isMobile),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapDown: (details) => showImageCardContextMenu(context, imageFile: widget.imageFile, position: details.globalPosition),
          onLongPressStart: (details) => showImageCardContextMenu(context, imageFile: widget.imageFile, position: details.globalPosition),
          child: _buildCardContent(context, colorScheme, isMobile),
        ),
      ),
    );
  }

  Widget _buildCardContent(BuildContext context, ColorScheme colorScheme, bool isMobile) {
    final isVideo = AppConstants.isVideoFile(widget.imageFile.path);
    final selected = widget.isSelected;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: AppMotion.durationOf(context, AppMotion.state),
        curve: AppMotion.enter,
        decoration: BoxDecoration(
          // 10, not the 12 a panel gets. `10c` draws these one step tighter
          // than a card, which is what keeps a grid of them from reading as
          // rounder than the columns holding it.
          borderRadius: BorderRadius.circular(AppRadius.md),
          color: colorScheme.surface,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.surfaceContainerHigh,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              // A resting lift, which these did not have before. The gallery
              // sits on the window backdrop rather than on a panel since the
              // restyle, and without a shadow the cards read as holes punched
              // in the mesh instead of as tiles laid on it.
              : [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        // A column, not a stack: the file name used to be burned onto the
        // bottom of the picture under a gradient scrim, which covered whatever
        // the picture had down there. It gets its own strip instead, so the
        // image is never obscured by its own label.
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnail(context, colorScheme),
                    if (_dimensions.isNotEmpty)
                      // Bounded on the right, not just placed on the left.
                      // The badge sizes to its text, and that text is a
                      // dimension, an aspect ratio and a file size — on a
                      // three-column grid it is routinely wider than the card,
                      // and it was being cut off mid-number by the card's own
                      // clip. Bounding it lets the label ellipsize instead,
                      // which loses the file size rather than half of it.
                      Positioned(
                        top: 6,
                        left: 6,
                        right: 6,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _buildMetaBadge(),
                        ),
                      ),
                    if ((_isHovering || isMobile) && !isVideo)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Center(child: _buildHoverActions(context)),
                      ),
                    if (selected)
                      Positioned(top: 6, right: 6, child: _buildSelectionBadge(colorScheme)),
                  ],
                ),
              ),
            ),
            _buildFooter(context, colorScheme),
          ],
        ),
      ),
    );
  }

  /// Dimensions and file size, on a scrim dark enough to read against whatever
  /// corner of the photo it lands on. See [_chipScrim] for why this is a flat
  /// fill rather than the frosted panel it used to be.
  Widget _buildMetaBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _chipScrim,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _dimensions,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: _overlayInk, height: AppType.tightHeight),
      ),
    );
  }

  /// The picture's position in the selection.
  ///
  /// A number rather than a tick: with several reference images the model is
  /// given them in this order, and the user has no other way to see it on the
  /// grid.
  Widget _buildSelectionBadge(ColorScheme colorScheme) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: _overlayScrim, blurRadius: 5, offset: const Offset(0, 1))],
      ),
      child: Text(
        '${widget.selectionNumber}',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  /// Compare / mask / crop, in one bar that appears only under the pointer —
  /// except on touch layouts, where it is permanent, which is the other reason
  /// it can no longer afford a blur.
  ///
  /// One capsule rather than three chips inside a fourth container, which is
  /// what this was: the nested fills read as buttons on top of a button.
  Widget _buildHoverActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: _barScrim,
        borderRadius: BorderRadius.circular(18),
      ),
      // The bar sits over a grid cell whose width is the column count's to
      // decide, and on a phone three columns leave less than the three
      // buttons measure. Scaling the capsule down keeps all three reachable
      // where a Row would put the third one past the edge of the picture.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildOverlayButton(
              icon: Icons.compare,
              onPressed: () => _handleCompare(context),
              tooltip: l10n.comparator,
            ),
            _buildOverlayButton(
              icon: Icons.brush,
              onPressed: () => _handleMask(context),
              tooltip: l10n.maskEditor,
            ),
            _buildOverlayButton(
              icon: Icons.crop,
              onPressed: () => _handleCrop(context),
              tooltip: l10n.cropAndResize,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      color: colorScheme.surface,
      child: Text(
        widget.imageFile.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return IconButton(
      icon: Icon(icon, size: 15, color: _overlayInk),
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  void _handleCompare(BuildContext context) {
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.sendToComparator(widget.imageFile.path);
  }

  void _handleMask(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.setMaskEditorSourceImage(widget.imageFile);
    appState.setWorkbenchTab(2); // Mask Editor
  }

  void _handleCrop(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final workbenchUIState = Provider.of<WorkbenchUIState>(context, listen: false);
    workbenchUIState.setCropResizeSourceImage(widget.imageFile);
    appState.setWorkbenchTab(3); // Crop Tab
  }
}
