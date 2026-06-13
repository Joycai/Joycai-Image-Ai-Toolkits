import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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

  Future<void> saveImage({
    required Uint8List bytes,
    required String targetPath,
  }) async {
    final file = File(targetPath);
    await file.writeAsBytes(bytes);
  }
}
