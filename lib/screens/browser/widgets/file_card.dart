import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../core/thumbnail_decode.dart';
import '../../../models/browser_file.dart';
import '../../../services/image_metadata_service.dart';
import '../../workbench/widgets/preview/video_thumbnail.dart';


class FileCard extends StatefulWidget {
  final BrowserFile file;
  final bool isSelected;
  final double thumbnailSize;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final Function(Offset) onSecondaryTap;

  const FileCard({
    super.key,
    required this.file,
    required this.isSelected,
    required this.thumbnailSize,
    required this.onTap,
    this.onDoubleTap,
    required this.onSecondaryTap,
  });

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  String _dimensions = "";

  @override
  void initState() {
    super.initState();
    if (widget.file.category == FileCategory.image) {
      _getImageDimensions();
    }
  }

  @override
  void didUpdateWidget(FileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path && widget.file.category == FileCategory.image) {
      _getImageDimensions();
    }
  }

  Future<void> _getImageDimensions() async {
    final metadata = await ImageMetadataService().getMetadata(widget.file.path);
    if (metadata != null && mounted) {
      setState(() {
        _dimensions = metadata.displayString;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onSecondaryTapDown: (details) => widget.onSecondaryTap(details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.state),
          curve: AppMotion.enter,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: colorScheme.surfaceContainerHighest.withAlpha(widget.isSelected ? 100 : 50),
            border: Border.all(
              // Only a selected card is outlined. The thumbnails supply their
              // own edges; a border on every one turns the grid into a mesh and
              // leaves the selected card with nothing of its own to say.
              color: widget.isSelected ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                                Expanded(
                                  child: widget.file.category == FileCategory.image
                                      ? Image(
                                          image: ResizeImage(
                                            widget.file.imageProvider,
                                            // Snapped to a ladder, not taken
                                            // at the painted size — see
                                            // [thumbnailDecodeWidth].
                                            width: thumbnailDecodeWidth(context, widget.thumbnailSize),
                                          ),
                                          fit: BoxFit.cover,
                                        )
                                      : widget.file.category == FileCategory.video
                                          ? VideoThumbnail(videoPath: widget.file.path, fit: BoxFit.cover)
                                          : Center(child: Icon(widget.file.icon, size: 48, color: widget.file.color.withAlpha(150))),
                                ),
                  
                  // A footer strip on the card, not a scrim on the picture.
                  // `B1` draws it the way the workbench's gallery card already
                  // does — the name below the image with a hairline between,
                  // rather than a black band covering whatever the thumbnail
                  // had along its bottom edge. Left-aligned for the same
                  // reason a filename is: the end is what gets truncated, so
                  // the beginning has to start in a predictable place.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLowest,
                      border: Border(
                        top: BorderSide(color: Theme.of(context).colorScheme.surfaceContainerHigh),
                      ),
                    ),
                    child: Text(
                      widget.file.name,
                      style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // A pill that wraps the figures, not a band across the card's full
              // width: the band reads as a caption the image happens to start
              // under, and it dims the top of every thumbnail to say it.
              if (_dimensions.isNotEmpty)
                Positioned(
                  top: 6,
                  left: 6,
                  right: 6,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _dimensions,
                        style: Theme.of(context).textTheme.labelSmall?.mono.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
