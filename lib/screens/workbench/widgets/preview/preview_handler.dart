import 'package:flutter/material.dart';

import 'image_preview_handler.dart';
import 'video_preview_handler.dart';

/// Strategy for previewing a single file type inside [MediaPreviewDialog].
///
/// To support a new file type, implement this interface and register it via
/// [PreviewRegistry.register]. Each handler is responsible for rendering both
/// the full-screen content (the page in the pager) and the small thumbnail
/// shown in the bottom strip.
abstract class PreviewHandler {
  /// Whether this handler can preview the file at [path] (usually an
  /// extension check).
  bool canHandle(String path);

  /// Builds the full-screen preview for [path].
  ///
  /// [isActive] is true only for the page currently shown in the pager, so
  /// handlers can lazily allocate heavy resources (e.g. video players) and
  /// release them when the page scrolls away.
  Widget buildContent(
    BuildContext context, {
    required String path,
    required bool isActive,
  });

  /// Builds the small thumbnail shown in the bottom strip for [path].
  Widget buildThumbnail(BuildContext context, {required String path});
}

/// Resolves the [PreviewHandler] responsible for a given file.
///
/// Handlers are tried in registration order; the first whose [canHandle]
/// returns true wins. [ImagePreviewHandler] is registered last and acts as the
/// fallback for anything no other handler claims.
class PreviewRegistry {
  PreviewRegistry._();

  static final List<PreviewHandler> _handlers = [
    VideoPreviewHandler(),
    // Keep the image handler last: it is the default fallback.
    ImagePreviewHandler(),
  ];

  static final ImagePreviewHandler _fallback = ImagePreviewHandler();

  /// Registers an additional [handler]. Inserted before the image fallback so
  /// it takes precedence over the default but after any earlier handlers.
  static void register(PreviewHandler handler) {
    _handlers.insert(_handlers.length - 1, handler);
  }

  /// Returns the handler for [path], or the image fallback if none matches.
  static PreviewHandler resolve(String path) {
    for (final handler in _handlers) {
      if (handler.canHandle(path)) return handler;
    }
    return _fallback;
  }
}
