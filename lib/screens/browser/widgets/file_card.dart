import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../models/browser_file.dart';

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
    try {
      final bytes = await File(widget.file.path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (mounted) {
        setState(() {
          final ratioStr = AppConstants.formatAspectRatio(image.width, image.height);
          final sizeStr = AppConstants.formatFileSize(widget.file.size);
          _dimensions = "${image.width}x${image.height} ($ratioStr) | $sizeStr";
        });
      }
    } catch (e) {
      // Ignore
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
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surfaceContainerHighest.withAlpha(widget.isSelected ? 100 : 50),
            border: Border.all(
              color: widget.isSelected ? colorScheme.primary : colorScheme.outlineVariant,
              width: widget.isSelected ? 2 : 1,
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
                        ? Image(image: widget.file.imageProvider, fit: BoxFit.cover)
                        : Center(child: Icon(widget.file.icon, size: 48, color: widget.file.color.withAlpha(150))),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.black54,
                    child: Text(
                      widget.file.name,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              if (_dimensions.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                    color: Colors.black.withAlpha(100),
                    child: Text(
                      _dimensions,
                      style: const TextStyle(color: Colors.white, fontSize: 8),
                      textAlign: TextAlign.center,
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
