import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';

/// The app's own scratch space under the OS temp directory, and the only thing
/// that reaps it.
///
/// Everything the app writes for itself rather than for the user lands under
/// `<temp>/joycai`: mask PNGs from the mask editor, crop/resize copies, the
/// downloader's page cache, video thumbnails. None of it was ever collected.
/// The OS clears its temp directory eventually, but "eventually" on a desktop
/// can be never — a machine that is not rebooted keeps every mask ever drawn.
///
/// [sweep] runs once at startup and takes the files that have gone cold.
/// [measure] and [clear] back the manual control in Settings, for the user who
/// wants the space back now rather than in a week.
///
/// **Directories are never removed, only the files inside them.** Two other
/// services (`VideoThumbnailService`, `WebScraperService`) hold a cached
/// `Directory` for their own subfolder and write through it without checking
/// that it still exists; pulling the folder out from under them turns their
/// next write into an exception.
class TempStorageService {
  TempStorageService._();
  static final TempStorageService instance = TempStorageService._();

  /// How long a scratch file has to go untouched before [sweep] takes it.
  ///
  /// A week: long enough that a mask or a crop is still there when someone
  /// comes back to a piece of work after a weekend, short enough that the
  /// directory does not accumulate across a season.
  static const Duration maxAge = Duration(days: 7);

  /// Owned by `VideoThumbnailService`, which prunes it on its own schedule
  /// (14 days, plus a file-count cap, refreshed on every cache hit). [sweep]
  /// leaves it to that policy rather than quietly overriding it with a shorter
  /// one. [measure] and [clear] *do* cover it: to the user asking what this
  /// costs, or asking for the space back, it is all one pile.
  static const String _foreignSubdirectory = 'video_thumbnails';

  bool _swept = false;

  Future<Directory> _root() async {
    final temp = await AppPaths.getTempDirectory();
    return Directory(p.join(temp, 'joycai'));
  }

  /// Deletes scratch files last modified more than [maxAge] ago.
  ///
  /// Runs at most once per session; safe to call unawaited from startup, which
  /// is also the only moment it is unambiguously safe to run at all — nothing
  /// has been dropped into the temporary workspace yet, and no task holds a
  /// mask. Best-effort throughout: a file that will not delete is skipped.
  Future<void> sweep({Duration maxAge = TempStorageService.maxAge}) async {
    if (_swept) return;
    _swept = true;

    try {
      final root = await _root();
      if (!await root.exists()) return;

      final cutoff = DateTime.now().subtract(maxAge);
      final foreign = p.join(root.path, _foreignSubdirectory);

      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (p.isWithin(foreign, entity.path)) continue;
        try {
          if ((await entity.stat()).modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('TempStorageService.sweep failed: $e');
    }
  }

  /// Total bytes currently held under `<temp>/joycai`, video thumbnails
  /// included. Returns 0 if the directory is absent or unreadable.
  Future<int> measure() async {
    try {
      final root = await _root();
      if (!await root.exists()) return 0;

      var total = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } catch (_) {}
      }
      return total;
    } catch (e) {
      debugPrint('TempStorageService.measure failed: $e');
      return 0;
    }
  }

  /// Deletes every scratch file regardless of age, and reports the bytes
  /// freed.
  ///
  /// Unlike [sweep] this can run while the app is in use, so it can take a
  /// mask or a crop that the temporary workspace is still pointing at. That is
  /// what the user asked for; the caller is expected to have said so first,
  /// and to refresh the gallery afterwards so the workspace drops the entries
  /// whose files have gone.
  Future<int> clear() async {
    try {
      final root = await _root();
      if (!await root.exists()) return 0;

      var freed = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          final size = await entity.length();
          await entity.delete();
          freed += size;
        } catch (_) {}
      }
      return freed;
    } catch (e) {
      debugPrint('TempStorageService.clear failed: $e');
      return 0;
    }
  }
}
