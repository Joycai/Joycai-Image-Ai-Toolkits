import 'dart:async';
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
///
/// Extraction is delegated to the platform (on Windows, the shell's own
/// thumbnail provider), which fails transiently on a file that is still being
/// written, still syncing down from a cloud drive, or momentarily locked by
/// the sync client. A failed attempt is therefore retried on a short backoff
/// ([retryDelays]) before the caller is told there is no thumbnail, and
/// concurrent requests for the same file share one attempt.
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  static const int _thumbnailSize = 150;
  static const int _quality = 75;

  /// Waits between extraction attempts: three tries over about seven seconds,
  /// long enough for a sync client to release a freshly written file.
  static const List<Duration> retryDelays = [Duration(seconds: 2), Duration(seconds: 5)];

  /// Thumbnails not accessed within this window are eligible for pruning.
  static const Duration _maxAge = Duration(days: 14);

  /// Hard cap on the number of cached thumbnails (oldest pruned first).
  static const int _maxFiles = 1000;

  Directory? _cacheDir;
  bool _cleaned = false;

  /// One extraction per video path at a time — a grid of cards scrolling past
  /// the same file must not spawn parallel native extractions.
  final Map<String, Future<String?>> _inFlight = {};

  /// Test seams: the native extractor and the cache directory, replaceable so
  /// retries can be exercised without a platform channel. The extractor
  /// returns true when it wrote `destFile`.
  @visibleForTesting
  Future<bool> Function(String srcFile, String destFile)? extractorOverride;
  @visibleForTesting
  Directory? cacheDirOverride;

  /// Test seam: how a retry waits. Defaults to a real delay.
  @visibleForTesting
  Future<void> Function(Duration delay) wait = Future<void>.delayed;

  Future<Directory> _getCacheDir() async {
    final cached = cacheDirOverride ?? _cacheDir;
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
  /// necessary. Returns null if the file is missing or every extraction
  /// attempt fails.
  Future<String?> getThumbnail(String videoPath) {
    final pending = _inFlight[videoPath];
    if (pending != null) return pending;
    final future = _getThumbnailWithRetry(videoPath).whenComplete(() {
      _inFlight.remove(videoPath);
    });
    _inFlight[videoPath] = future;
    return future;
  }

  Future<String?> _getThumbnailWithRetry(String videoPath) async {
    for (var attempt = 0; ; attempt++) {
      final result = await _tryGetThumbnail(videoPath);
      if (result.path != null || !result.retryable) return result.path;
      if (attempt >= retryDelays.length) return null;
      await wait(retryDelays[attempt]);
    }
  }

  Future<_Attempt> _tryGetThumbnail(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return const _Attempt.gone();

      final cacheDir = await _getCacheDir();
      final stat = await file.stat();
      final key = '${videoPath}_${stat.modified.millisecondsSinceEpoch}_${stat.size}';
      final hash = md5.convert(utf8.encode(key)).toString();
      final cachePath = '${cacheDir.path}/$hash.jpg';
      final cacheFile = File(cachePath);

      if (await cacheFile.exists()) {
        // Touch so cleanup treats recently viewed thumbnails as fresh.
        try {
          await cacheFile.setLastModified(DateTime.now());
        } catch (_) {}
        return _Attempt.found(cachePath);
      }

      // Write to a unique temp file first, then rename into place. rename is
      // atomic on the same filesystem, so concurrent generators never observe
      // a half-written thumbnail.
      final tmpPath = '$cachePath.${DateTime.now().microsecondsSinceEpoch}.tmp';
      final tmpFile = File(tmpPath);

      final success = await _extract(videoPath, tmpPath);

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
        if (await cacheFile.exists()) return _Attempt.found(cachePath);
      } else if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      return const _Attempt.failed();
    } catch (e) {
      debugPrint('VideoThumbnailService.getThumbnail failed for $videoPath: $e');
      return const _Attempt.failed();
    }
  }

  Future<bool> _extract(String srcFile, String destFile) {
    final override = extractorOverride;
    if (override != null) return override(srcFile, destFile);
    return FcNativeVideoThumbnail().saveThumbnailToFile(
      srcFile: srcFile,
      destFile: destFile,
      width: _thumbnailSize,
      height: _thumbnailSize,
      quality: _quality,
    );
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
        survivors.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
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

/// Outcome of one extraction attempt: a thumbnail, a transient failure worth
/// retrying, or a missing source file that no retry can help.
class _Attempt {
  final String? path;
  final bool retryable;

  const _Attempt.found(String this.path) : retryable = false;
  const _Attempt.failed() : path = null, retryable = true;
  const _Attempt.gone() : path = null, retryable = false;
}
