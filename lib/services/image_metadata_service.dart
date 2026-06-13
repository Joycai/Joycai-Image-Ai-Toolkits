import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';

import '../core/constants.dart';

class ImageMetadata {
  final int width;
  final int height;
  final int fileSize;
  final String aspectRatio;
  final String sizeString;

  ImageMetadata({
    required this.width,
    required this.height,
    required this.fileSize,
    required this.aspectRatio,
    required this.sizeString,
  });

  String get displayString => width > 0 ? "${width}x$height ($aspectRatio) | $sizeString" : sizeString;

  Map<String, String> get params => {
    if (width > 0) "Width": "$width px",
    if (height > 0) "Height": "$height px",
    if (aspectRatio.isNotEmpty) "Aspect Ratio": aspectRatio,
    "File Size": sizeString,
  };
}

class ImageMetadataService {
  static final ImageMetadataService _instance = ImageMetadataService._internal();
  factory ImageMetadataService() => _instance;
  ImageMetadataService._internal();

  // Simple in-memory cache
  final Map<String, ImageMetadata> _cache = {};
  final int _maxCacheSize = 500;

  Future<ImageMetadata?> getMetadata(String path) async {
    // 1. Check cache
    if (_cache.containsKey(path)) {
      return _cache[path];
    }

    try {
      final file = File(path);
      if (!await file.exists()) return null;

      if (AppConstants.isVideoFile(path)) {
        final fileSize = await file.length();
        final metadata = ImageMetadata(
          width: 0,
          height: 0,
          fileSize: fileSize,
          aspectRatio: "",
          sizeString: AppConstants.formatFileSize(fileSize),
        );
        _cache[path] = metadata;
        return metadata;
      }

      final result = ImageSizeGetter.getSizeResult(FileInput(file));
      final size = result.size;
      final fileSize = await file.length();

      final metadata = ImageMetadata(
        width: size.width,
        height: size.height,
        fileSize: fileSize,
        aspectRatio: AppConstants.formatAspectRatio(size.width, size.height),
        sizeString: AppConstants.formatFileSize(fileSize),
      );

      // 2. Update cache with basic LRU policy (evict oldest if full)
      if (_cache.length >= _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }
      _cache[path] = metadata;

      return metadata;
    } catch (e) {
      debugPrint('Error loading metadata for $path: $e');
      return null;
    }
  }

  void clearCache() => _cache.clear();
  
  void evict(String path) => _cache.remove(path);
}
