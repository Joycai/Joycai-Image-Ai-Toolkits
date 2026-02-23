import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum SamplingMethod {
  nearest,
  linear,
  cubic,
  lanczos,
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
    final bytes = await File(sourcePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) throw Exception("Failed to decode image");

    // 1. Crop
    if (cropX != null && cropY != null && cropWidth != null && cropHeight != null) {
      image = img.copyCrop(
        image, 
        x: cropX, 
        y: cropY, 
        width: cropWidth, 
        height: cropHeight
      );
    }

    // 2. Resize
    if (width != null || height != null) {
      img.Interpolation filter;
      switch (sampling) {
        case SamplingMethod.nearest: filter = img.Interpolation.nearest; break;
        case SamplingMethod.linear: filter = img.Interpolation.linear; break;
        case SamplingMethod.cubic: filter = img.Interpolation.cubic; break;
        case SamplingMethod.lanczos: filter = img.Interpolation.average; break; // Lanczos not directly mapped, use average or best available
      }

      image = img.copyResize(
        image,
        width: width,
        height: height,
        maintainAspect: maintainAspectRatio,
        interpolation: filter,
      );
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  Future<void> saveImage({
    required Uint8List bytes,
    required String targetPath,
  }) async {
    final file = File(targetPath);
    await file.writeAsBytes(bytes);
  }
}
