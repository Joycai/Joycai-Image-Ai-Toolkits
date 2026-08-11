import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';

enum SamplingMethod {
  nearest,
  linear,
  cubic,
  lanczos,
}

class _ImageProcessParams {
  final String sourcePath;
  final int? cropX;
  final int? cropY;
  final int? cropWidth;
  final int? cropHeight;
  final int? width;
  final int? height;
  final bool maintainAspectRatio;
  final SamplingMethod sampling;

  _ImageProcessParams({
    required this.sourcePath,
    this.cropX,
    this.cropY,
    this.cropWidth,
    this.cropHeight,
    this.width,
    this.height,
    required this.maintainAspectRatio,
    required this.sampling,
  });
}

Uint8List _runImageProcess(_ImageProcessParams params) {
  final file = File(params.sourcePath);
  final bytes = file.readAsBytesSync();
  img.Image? image = img.decodeImage(bytes);
  if (image == null) throw Exception("Failed to decode image");

  // 1. Crop
  if (params.cropX != null && params.cropY != null && params.cropWidth != null && params.cropHeight != null) {
    image = img.copyCrop(
      image, 
      x: params.cropX!, 
      y: params.cropY!, 
      width: params.cropWidth!, 
      height: params.cropHeight!
    );
  }

  // 2. Resize
  if (params.width != null || params.height != null) {
    img.Interpolation filter;
    switch (params.sampling) {
      case SamplingMethod.nearest: filter = img.Interpolation.nearest; break;
      case SamplingMethod.linear: filter = img.Interpolation.linear; break;
      case SamplingMethod.cubic: filter = img.Interpolation.cubic; break;
      case SamplingMethod.lanczos: filter = img.Interpolation.average; break; // Lanczos not directly mapped, use average
    }

    image = img.copyResize(
      image,
      width: params.width,
      height: params.height,
      maintainAspect: params.maintainAspectRatio,
      interpolation: filter,
    );
  }

  return Uint8List.fromList(img.encodePng(image));
}

class ImageProcessingService {
  static final ImageProcessingService _instance = ImageProcessingService._internal();
  factory ImageProcessingService() => _instance;
  ImageProcessingService._internal();

  Future<Uint8List> processImage({
    required String sourcePath,
    int? cropX,
    int? cropY,
    int? cropWidth,
    int? cropHeight,
    int? width,
    int? height,
    bool maintainAspectRatio = true,
    SamplingMethod sampling = SamplingMethod.lanczos,
  }) async {
    final params = _ImageProcessParams(
      sourcePath: sourcePath,
      cropX: cropX,
      cropY: cropY,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
      width: width,
      height: height,
      maintainAspectRatio: maintainAspectRatio,
      sampling: sampling,
    );
    return await compute(_runImageProcess, params);
  }

  /// Writes [bytes] to [targetPath].
  ///
  /// [allowOverwrite] is required and has no default on purpose. Replacing a
  /// file the user already has is the destructive half of this method, and the
  /// only thing standing between the two behaviours used to be whichever path
  /// string the caller happened to build — a copy and an overwrite went down
  /// the same line. A call site now has to state which one it means, and a new
  /// one cannot silently inherit the destructive reading.
  ///
  /// The check lives here rather than only in the dialog that asks the user,
  /// because a UI guard protects the one path that goes through that UI. This
  /// protects the file.
  Future<void> saveImage({
    required Uint8List bytes,
    required String targetPath,
    required bool allowOverwrite,
  }) async {
    final file = File(targetPath);

    if (!allowOverwrite && await file.exists()) {
      throw FileSystemException(
        'Refusing to overwrite an existing file: pass allowOverwrite to replace it',
        targetPath,
      );
    }

    await file.writeAsBytes(bytes);
  }

  /// Where a "save a copy" from the crop/resize editor lands, resolved against
  /// what is actually on disk.
  ///
  /// One resolver for three readers — the editor's output strip, the overwrite
  /// dialog's "save a copy instead" hint, and the save itself. They used to
  /// derive it separately and disagree: the strip advertised
  /// `Temporary Workspace / crop_photo.jpg` while the write produced
  /// `<temp>/joycai/processed/crop_photo_1754899200000.png` — a different
  /// name, a different extension and a folder it never mentioned. A dialog
  /// that names the file it is about to write has to be right about it, so
  /// there is now one place to be right in.
  ///
  /// The name is deterministic (`<base>_crop.png`) rather than
  /// timestamp-stamped, because a name nobody can predict cannot be shown to
  /// anyone before the fact. Collisions take a numeric suffix instead.
  Future<CropCopyTarget> resolveCropCopyTarget(String sourcePath) async {
    final tempDir = await AppPaths.getTempDirectory();
    final directory = Directory(p.join(tempDir, 'joycai', 'processed'));

    final base = p.basenameWithoutExtension(sourcePath);
    // Always .png: `_runImageProcess` encodes PNG regardless of the source
    // format, so this is the extension the bytes will actually be.
    var name = '${base}_crop.png';
    for (var n = 2; File(p.join(directory.path, name)).existsSync(); n++) {
      name = '${base}_crop_$n.png';
    }

    return CropCopyTarget(directory: directory, fileName: name);
  }
}

/// The resolved destination of a crop/resize copy.
class CropCopyTarget {
  /// May not exist yet — [ensureExists] creates it.
  final Directory directory;
  final String fileName;

  const CropCopyTarget({required this.directory, required this.fileName});

  String get path => p.join(directory.path, fileName);

  void ensureExists() {
    if (!directory.existsSync()) directory.createSync(recursive: true);
  }
}
