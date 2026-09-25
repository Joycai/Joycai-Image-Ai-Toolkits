import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../models/image_layer.dart';

/// Flattens a layer decomposition back into one picture — the layer
/// canvas's 「导出合成图」 (design `A7 · 7a` ⑥).
///
/// The canvas is the base's pixel grid, because that is what the boxes are
/// measured in (docs/api/volcengine-ark.md §7). Each layer is stretched into
/// its box, as the canvas draws it; a layer with no box covers the whole
/// base. A hidden base leaves the ground transparent rather than shrinking
/// the canvas, so the layers stay where they were.
class LayerCompositeService {
  /// Composites [layers] (the visible ones, bottom to top) onto a
  /// [width]×[height] transparent canvas and returns PNG bytes. Runs in an
  /// isolate: a decode and a resize per layer at several megapixels would
  /// stall the UI.
  static Future<Uint8List> composite(List<ImageLayer> layers, int width, int height) {
    final input = [
      for (final l in layers)
        (l.path, l.box == null ? null : [l.box!.left, l.box!.top, l.box!.width, l.box!.height]),
    ];
    return compute(_composite, (input, width, height));
  }

  /// Writes [png] next to [basePath] as `<stem>_composite.png`, numbering
  /// `(2)`, `(3)`… when that is taken, and returns the path.
  static Future<String> save(String basePath, Uint8List png) async {
    final dir = p.dirname(basePath);
    final stem = '${p.basenameWithoutExtension(basePath)}_composite';
    var target = p.join(dir, '$stem.png');
    for (var n = 2; await File(target).exists(); n++) {
      target = p.join(dir, '$stem ($n).png');
    }
    await File(target).writeAsBytes(png, flush: true);
    return target;
  }
}

Uint8List _composite((List<(String, List<int>?)>, int, int) args) {
  final (layers, width, height) = args;
  final canvas = img.Image(width: width, height: height, numChannels: 4);
  for (final (path, box) in layers) {
    final decoded = img.decodeImage(File(path).readAsBytesSync());
    if (decoded == null) continue;
    final src = decoded.numChannels == 4
        ? decoded
        : decoded.convert(numChannels: 4, alpha: decoded.maxChannelValue);
    img.compositeImage(
      canvas,
      src,
      dstX: box?[0] ?? 0,
      dstY: box?[1] ?? 0,
      dstW: box?[2] ?? width,
      dstH: box?[3] ?? height,
    );
  }
  return img.encodePng(canvas);
}
