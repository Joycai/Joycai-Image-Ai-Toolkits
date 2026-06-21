import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/responsive.dart';
import '../../../models/app_image.dart';
import '../../../services/image_metadata_service.dart';
import '../../../services/video_thumbnail_service.dart';
import '../../../state/app_state.dart';
import '../../../state/workbench_ui_state.dart';
import 'image_card_context_menu.dart';

/// A single thumbnail tile in the gallery grid. Handles its own thumbnail
/// loading and hover/selection chrome; all file actions are delegated to
/// [showImageCardContextMenu].
class ImageCard extends StatefulWidget {
  final AppImage imageFile;
  final bool isSelected;
  final bool isResult;
  final double thumbnailSize;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  const ImageCard({
    super.key,
    required this.imageFile,
    required this.isSelected,
    required this.isResult,
    required this.thumbnailSize,
    required this.onTap,
    this.onDoubleTap,
  });

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
    _getImageDimensions();
    _loadVideoThumbnail();
  }

  @override
  void didUpdateWidget(covariant ImageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile.path != widget.imageFile.path) {
      setState(() {
        _dimensions = "";
        _videoThumbnailPath = null;
      });
      _getImageDimensions();
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
              color: _videoThumbnailPath != null ? Colors.black26 : Colors.transparent,
            ),
            Icon(
              Icons.play_circle_filled_rounded,
              size: 40,
              color: Colors.white.withAlpha((255 * 0.9).round()),
            ),
            Positioned(
              bottom: 4,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, size: 10, color: Colors.white),
                    SizedBox(width: 2),
                    Text(
                      "VIDEO",
                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
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
        width: width != null ? (width * MediaQuery.of(context).devicePixelRatio).round() : (widget.thumbnailSize * MediaQuery.of(context).devicePixelRatio).round(),
      ),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, color: Colors.grey),
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.5).round()),
          border: Border.all(
            color: widget.isSelected ? colorScheme.primary : colorScheme.outlineVariant.withAlpha((255 * 0.4).round()),
            width: widget.isSelected ? 2 : 1,
          ),
          boxShadow: widget.isSelected ? [
            BoxShadow(
              color: colorScheme.primary.withAlpha((255 * 0.2).round()),
              blurRadius: 8,
              spreadRadius: 2,
            )
          ] : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildThumbnail(context, colorScheme),

            if (_dimensions.isNotEmpty)
              Positioned(
                top: 7,
                left: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(158),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _dimensions,
                    style: const TextStyle(color: Color(0xFFD6D9E0), fontSize: 9.5),
                  ),
                ),
              ),

            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 14, 9, 7),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD0060708)],
                  ),
                ),
                child: Text(
                  widget.imageFile.name,
                  style: const TextStyle(
                    color: Color(0xFFE8EAEF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Overlay Buttons — bottom-center pill above name label
            if ((_isHovering || isMobile) && !isVideo)
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildOverlayButton(
                          icon: Icons.compare,
                          onPressed: () => _handleCompare(context),
                          tooltip: 'Compare',
                        ),
                        _buildOverlayButton(
                          icon: Icons.brush,
                          onPressed: () => _handleMask(context),
                          tooltip: 'Mask',
                        ),
                        _buildOverlayButton(
                          icon: Icons.crop,
                          onPressed: () => _handleCrop(context),
                          tooltip: 'Crop',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            if (widget.isSelected)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(150),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IconButton(
        icon: Icon(icon, size: 16, color: Colors.white),
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
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
