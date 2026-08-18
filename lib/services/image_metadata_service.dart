import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  /// The one-line badge an image card carries. Multiplication sign and middot
  /// rather than "x" and a pipe: at the 9-10px this is drawn, a lowercase x
  /// reads as part of the number beside it.
  String get displayString => width > 0 ? "$width×$height ($aspectRatio) · $sizeString" : sizeString;

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

  /// Reads already under way, so the same file is measured once no matter how
  /// many cards ask for it. A scroll that mounts and unmounts the same tile
  /// twice, or two views showing one picture, used to issue the read twice.
  final Map<String, Future<ImageMetadata?>> _inFlight = {};

  /// What is already known about [path], without touching the disk.
  ///
  /// Lets a thumbnail that has been measured before paint its badge on the
  /// first frame instead of scheduling a read and a `setState` for a value it
  /// already had — which is the common case when scrolling back over a grid.
  ImageMetadata? peek(String path) => _cache[path];

  Future<ImageMetadata?> getMetadata(String path) {
    final cached = _cache[path];
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[path];
    if (pending != null) return pending;

    // Queued through the scheduler rather than started immediately.
    //
    // [ImageSizeGetter.getSizeResult] is synchronous file I/O, and this is
    // called from every thumbnail's initState — flinging the grid mounts a
    // couple of dozen cards in one frame, and every one of those reads landed
    // back-to-back on the UI isolate as soon as the `exists` check resolved.
    // `scheduleTask` at [Priority.animation] runs them in the slack after a
    // frame and stops when the frame budget is gone, so the reads spread across
    // frames instead of stalling one.
    final future = SchedulerBinding.instance
        .scheduleTask(() => _read(path), Priority.animation)
        .whenComplete(() => _inFlight.remove(path));
    _inFlight[path] = future;
    return future;
  }

  Future<ImageMetadata?> _read(String path) async {
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
        _putInCache(path, metadata);
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

      _putInCache(path, metadata);

      return metadata;
    } catch (e) {
      debugPrint('Error loading metadata for $path: $e');
      return null;
    }
  }

  // Insert into cache with a basic LRU policy (evict oldest if full).
  void _putInCache(String path, ImageMetadata metadata) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[path] = metadata;
  }

  void clearCache() => _cache.clear();
  
  void evict(String path) => _cache.remove(path);
}
