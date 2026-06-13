import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Generates and caches video thumbnails on disk, and prunes stale entries.
///
/// Centralizes the logic previously duplicated in the gallery and preview
/// dialog. Thumbnails are written atomically (temp file + rename) so two
/// widgets generating the same thumbnail concurrently can't produce a
/// partially written file. [cleanup] prunes orphaned thumbnails so the cache
/// directory does not grow without bound.
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  static const int _thumbnailSize = 150;
  static const int _quality = 75;

  /// Thumbnails not accessed within this window are eligible for pruning.
  static const Duration _maxAge = Duration(days: 14);

  /// Hard cap on the number of cached thumbnails (oldest pruned first).
  static const int _maxFiles = 1000;

  Directory? _cacheDir;
  bool _cleaned = false;

  Future<Directory> _getCacheDir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/joycai/video_thumbnails');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Returns the path to a cached thumbnail for [videoPath], generating it if
  /// necessary. Returns null if the file is missing or generation fails.
  Future<String?> getThumbnail(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return null;

      final cacheDir = await _getCacheDir();
      final stat = await file.stat();
      final key =
          '${videoPath}_${stat.modified.millisecondsSinceEpoch}_${stat.size}';
      final hash = md5.convert(utf8.encode(key)).toString();
      final cachePath = '${cacheDir.path}/$hash.jpg';
      final cacheFile = File(cachePath);

      if (await cacheFile.exists()) {
        // Touch so cleanup treats recently viewed thumbnails as fresh.
        try {
          await cacheFile.setLastModified(DateTime.now());
        } catch (_) {}
        return cachePath;
      }

      // Write to a unique temp file first, then rename into place. rename is
      // atomic on the same filesystem, so concurrent generators never observe
      // a half-written thumbnail.
      final tmpPath = '$cachePath.${DateTime.now().microsecondsSinceEpoch}.tmp';
      final tmpFile = File(tmpPath);

      final plugin = FcNativeVideoThumbnail();
      final success = await plugin.saveThumbnailToFile(
        srcFile: videoPath,
        destFile: tmpPath,
        width: _thumbnailSize,
        height: _thumbnailSize,
        quality: _quality,
      );

      if (success && await tmpFile.exists()) {
        try {
          await tmpFile.rename(cachePath);
        } catch (_) {
          // Another generator likely won the race; discard our temp file.
          if (await tmpFile.exists()) {
            try {
              await tmpFile.delete();
            } catch (_) {}
          }
        }
        if (await cacheFile.exists()) return cachePath;
      } else if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('VideoThumbnailService.getThumbnail failed for $videoPath: $e');
      return null;
    }
  }

  /// Prunes stale and excess thumbnails plus leftover temp files. Runs at most
  /// once per app session; safe to call from startup.
  Future<void> cleanup() async {
    if (_cleaned) return;
    _cleaned = true;
    try {
      final cacheDir = await _getCacheDir();
      final now = DateTime.now();
      final survivors = <File>[];

      for (final entity in cacheDir.listSync()) {
        if (entity is! File) continue;
        try {
          if (entity.path.endsWith('.tmp')) {
            // Leftover from an interrupted write.
            entity.deleteSync();
            continue;
          }
          if (!entity.path.endsWith('.jpg')) continue;
          if (now.difference(entity.statSync().modified) > _maxAge) {
            entity.deleteSync();
          } else {
            survivors.add(entity);
          }
        } catch (_) {}
      }

      // Enforce the hard file-count cap, deleting oldest first.
      if (survivors.length > _maxFiles) {
        survivors.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
        );
        final excess = survivors.length - _maxFiles;
        for (var i = 0; i < excess; i++) {
          try {
            survivors[i].deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('VideoThumbnailService.cleanup failed: $e');
    }
  }
}
