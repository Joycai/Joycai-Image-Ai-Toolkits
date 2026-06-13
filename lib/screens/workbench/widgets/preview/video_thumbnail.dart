import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../services/video_thumbnail_service.dart';

/// Renders a poster frame for a video file, generated lazily via
/// [VideoThumbnailService]. Used both in the bottom thumbnail strip and as the
/// loading placeholder behind a still-initializing video player.
class VideoThumbnail extends StatefulWidget {
  final String videoPath;
  final BoxFit fit;
  final bool showPlayIcon;

  const VideoThumbnail({
    super.key,
    required this.videoPath,
    this.fit = BoxFit.cover,
    this.showPlayIcon = true,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      setState(() {
        _thumbnailPath = null;
      });
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final path = widget.videoPath;
    final cachePath = await VideoThumbnailService.instance.getThumbnail(path);
    // Widget may have been recycled to a different video while awaiting.
    if (cachePath != null && mounted && widget.videoPath == path) {
      setState(() {
        _thumbnailPath = cachePath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(_thumbnailPath!), fit: widget.fit),
          Container(color: Colors.black26),
          if (widget.showPlayIcon)
            const Center(
              child: Icon(Icons.play_circle_outline, color: Colors.white, size: 24),
            ),
        ],
      );
    }
    return Container(
      color: Colors.white10,
      child: Center(
        child: widget.showPlayIcon
            ? const Icon(Icons.play_circle_outline, color: Colors.white, size: 24)
            : const SizedBox.shrink(),
      ),
    );
  }
}
