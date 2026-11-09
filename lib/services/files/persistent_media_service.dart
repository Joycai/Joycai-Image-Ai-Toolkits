import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/app_paths.dart';

/// Durable inputs/results are never part of TempStorageService's scratch tree.
/// Accepted files are retained until explicitly deleted; no age-based collection.
class PersistentMediaService {
  PersistentMediaService({Future<String> Function()? dataDirectory})
    : _dataDirectory = dataDirectory ?? AppPaths.getDataDirectory;

  static final instance = PersistentMediaService();
  static const _channel = MethodChannel('joycai/directory_access');
  final Future<String> Function() _dataDirectory;

  Future<Directory> resultsDirectory() async {
    final dir = Directory(p.join(await _dataDirectory(), 'media', 'results'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Deterministic destination makes a copy completed before a crash reusable.
  /// Sibling image/text sidecars retain the same stem. Never overwrite a result.
  Future<String> migrateResult(String source) async {
    final root = await resultsDirectory();
    final stem = p.withoutExtension(p.normalize(p.absolute(source)));
    final name = 'legacy_${const Uuid().v5(Namespace.url.value, stem)}_${p.basename(source)}';
    final destination = File(p.join(root.path, name));
    final digest = await sha256.bind(File(source).openRead()).first;
    if (!await destination.exists()) {
      // Staging lives beside the final file, on the same persistent volume.
      final dir = Directory(p.join(root.path, '.migration-${const Uuid().v4()}'));
      try {
        final copied = File(await _copy(source, dir));
        if (await sha256.bind(copied.openRead()).first != digest) {
          throw FileSystemException('Source changed during migration', source);
        }
        await copied.rename(destination.path);
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }
    if (await sha256.bind(destination.openRead()).first != digest) {
      throw FileSystemException('Migration destination differs from source', destination.path);
    }
    return destination.path;
  }

  /// Keep received image bytes when a selected volume disappears after the
  /// initial writable check. A partial file is never published as a result.
  Future<File> saveResult(
    Uint8List bytes,
    String preferredPath, {
    bool allowFallback = true,
  }) async {
    Future<File> write(String path) async {
      final file = File(path);
      if (await file.exists()) {
        if (listEquals(await file.readAsBytes(), bytes)) return file;
        throw FileSystemException('Result path contains a different file', path);
      }
      final partial = File('$path.${const Uuid().v4()}.partial');
      try {
        await partial.writeAsBytes(bytes, flush: true);
        return await partial.rename(path);
      } finally {
        if (await partial.exists()) await partial.delete();
      }
    }

    try {
      return await write(preferredPath);
    } on FileSystemException {
      if (!allowFallback) rethrow;
      final root = await resultsDirectory();
      // Keep results flat: the gallery's result scan intentionally lists only
      // direct children. A unique name also avoids overwriting prior results.
      return write(p.join(root.path, '${const Uuid().v4()}_${p.basename(preferredPath)}'));
    }
  }

  Future<String> importFile(String source, {Uint8List? appleBookmark}) async {
    final dir = Directory(p.join(await _dataDirectory(), 'media', 'imports', const Uuid().v4()));
    try {
      return await _copy(source, dir, appleBookmark: appleBookmark);
    } catch (_) {
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// Copies a complete input set before the caller publishes a queued task.
  /// Originals are untouched. Duplicated references share a copy within this set.
  Future<Map<String, String>> snapshot(Iterable<String> sources) async {
    final paths = sources.where((path) => path.isNotEmpty).toSet();
    if (paths.isEmpty) return {};
    final root = Directory(p.join(await _dataDirectory(), 'media', 'tasks', const Uuid().v4()));
    final copies = <String, String>{};
    try {
      for (final source in paths) {
        copies[source] = await _copy(source, Directory(p.join(root.path, '${copies.length}')));
      }
      return copies;
    } catch (_) {
      if (await root.exists()) await root.delete(recursive: true);
      rethrow;
    }
  }

  Future<String> _copy(String source, Directory dir, {Uint8List? appleBookmark}) async {
    await dir.create(recursive: true);
    final destination = p.join(dir.path, p.basename(source));
    final partial = '$destination.partial';
    if (Platform.isMacOS && appleBookmark != null && appleBookmark.isNotEmpty) {
      // Native code retains the exact resolved URL until the copy completes.
      await _channel.invokeMethod<void>('copyDrop', {
        'bookmark': appleBookmark,
        'destination': partial,
      });
    } else {
      // Stream into a newly created file rather than inheriting read-only or
      // locked source permissions. Large video inputs stay bounded in memory.
      final handle = await File(partial).open(mode: FileMode.write);
      try {
        await for (final chunk in File(source).openRead()) {
          await handle.writeFrom(chunk);
        }
        await handle.flush();
      } finally {
        await handle.close();
      }
    }
    await File(partial).rename(destination);
    return destination;
  }
}
