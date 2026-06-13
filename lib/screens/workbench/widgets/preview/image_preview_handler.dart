import 'dart:io';

import 'package:flutter/material.dart';

import 'preview_handler.dart';

/// Preview handler for still images. Also serves as the default fallback for
/// any file type no other handler claims (see [PreviewRegistry]).
class ImagePreviewHandler implements PreviewHandler {
  @override
  bool canHandle(String path) => true;

  @override
  Widget buildContent(
    BuildContext context, {
    required String path,
    required bool isActive,
  }) {
    return Hero(
      tag: path,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5.0,
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image, color: Colors.white54, size: 64),
        ),
      ),
    );
  }

  @override
  Widget buildThumbnail(BuildContext context, {required String path}) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 120,
    );
  }
}
