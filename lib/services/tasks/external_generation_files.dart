import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../core/image_magic.dart';
import 'generation_submission_error.dart';
import 'reference_folder_rule.dart';

/// Only checked reference bytes and task-owned output paths cross this boundary.
class ExternalGenerationFiles {
  static const maxBytes = 20 * 1024 * 1024;
  static const maxPixels = 64 * 1024 * 1024;

  static Future<Uint8List> read(String path) async {
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != p.normalize(p.absolute(path))) {
      throw const GenerationSubmissionError('fileNotFound', 'The image file no longer exists.');
    }
    // Bound the actual read as well as the initial stat (the file can grow).
    final out = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (out.length + chunk.length > maxBytes) {
        throw const GenerationSubmissionError('imageTooLarge', 'Images must be at most 20 MiB.');
      }
      out.add(chunk);
    }
    if (await file.resolveSymbolicLinks() != p.normalize(p.absolute(path))) {
      throw const GenerationSubmissionError('fileChanged', 'The image path changed while reading.');
    }
    return out.takeBytes();
  }

  static Future<Map<String, int>> dimensions(Uint8List bytes, {bool decode = false}) =>
      Isolate.run(() {
        try {
          if (imageMimeFromBytes(bytes) == null) throw const FormatException();
          final decoder = img.findDecoderForData(bytes);
          final info = decoder?.startDecode(bytes);
          if (info == null ||
              info.width <= 0 ||
              info.height <= 0 ||
              info.width * info.height > maxPixels ||
              // The executor/compressor may decode the whole reference later.
              // Bound total animation pixels, not only the first frame's canvas.
              info.numFrames > maxPixels ~/ (info.width * info.height)) {
            throw const FormatException();
          }
          // Frame descriptors are independent of the canvas header. Reject a
          // forged small canvas hiding an oversized frame before allocation.
          final frames = switch (info) {
            img.GifInfo() => info.frames.map((f) => (f.x, f.y, f.width, f.height)),
            img.PngInfo() => info.frames.map((f) => (f.xOffset, f.yOffset, f.width, f.height)),
            img.WebPInfo() => info.frames.map((f) => (f.x, f.y, f.width, f.height)),
            _ => const <(int, int, int, int)>[],
          };
          for (final (x, y, width, height) in frames) {
            if (x < 0 ||
                y < 0 ||
                width <= 0 ||
                height <= 0 ||
                x + width > info.width ||
                y + height > info.height) {
              throw const FormatException();
            }
          }
          if (decode && decoder!.decodeFrame(0) == null) throw const FormatException();
          return {'width': info.width, 'height': info.height};
        } catch (_) {
          throw const GenerationSubmissionError(
            'invalidImage',
            'Use a valid image with at most 64 megapixels across all frames.',
          );
        }
      });

  static Future<String> stage(
    String path,
    List<String> roots,
    Directory directory,
    int index, {
    bool registeredOutput = false,
  }) async {
    final canonical = await File(path).resolveSymbolicLinks();
    var allowed = registeredOutput;
    if (!registeredOutput) {
      for (final root in roots) {
        try {
          if (await ReferenceFolderRule.parse(root).allows(canonical)) {
            allowed = true;
          }
        } on FileSystemException {
          continue;
        } on FormatException {
          continue;
        }
      }
    }
    if (!allowed) {
      throw const GenerationSubmissionError(
        'referenceNotAllowed',
        'Choose an image inside an allowed reference folder in MCP settings.',
      );
    }
    final bytes = await read(canonical);
    if (await File(canonical).resolveSymbolicLinks() != canonical) {
      throw const GenerationSubmissionError(
        'referenceChanged',
        'The reference path changed while reading.',
      );
    }
    await dimensions(bytes, decode: true);
    final extension = imageExtensionFromBytes(bytes);
    if (imageMimeFromBytes(bytes) == null) {
      throw const GenerationSubmissionError('invalidImage', 'Unsupported reference image format.');
    }
    await directory.create(recursive: true);
    final copy = File(p.join(directory.path, '$index$extension'));
    await copy.writeAsBytes(bytes, flush: true);
    return copy.path;
  }

  static Future<Uint8List> preview(Uint8List bytes) => Isolate.run(() {
    final decoded = img.decodeImage(bytes, frame: 0);
    if (decoded == null) {
      throw const GenerationSubmissionError('invalidImage', 'Invalid output image.');
    }
    final resized = decoded.width > 1024 || decoded.height > 1024
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1024 : null,
            height: decoded.height > decoded.width ? 1024 : null,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  });
}
