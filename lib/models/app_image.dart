import 'dart:io';

/// Cross-platform image abstraction
class AppImage {
  final String path;
  final String name;

  /// Scanned modification time and size; empty before a file has been scanned.
  /// Selection identity stays path-based across edits.
  final String version;

  /// Last-modified timestamp read off-thread during scanning or import; null
  /// when constructed from a path without statting disk.
  final DateTime? modified;

  /// File size in bytes read alongside [modified]; null when unavailable.
  final int? size;

  AppImage({required this.path, required this.name, this.version = '', this.modified, this.size});

  factory AppImage.fromFile(File file, {String version = '', DateTime? modified, int? size}) {
    return AppImage(
      path: file.path,
      name: file.path.split(Platform.pathSeparator).last,
      version: version,
      modified: modified,
      size: size,
    );
  }

  /// Builds an [AppImage] after reading its modification time and size
  /// asynchronously, falling back to path-only metadata when unreadable.
  static Future<AppImage> fromPathAsync(String path, {String? name}) async {
    final resolvedName = name ?? path.split(Platform.pathSeparator).last;
    try {
      final stat = await File(path).stat();
      if (stat.type == FileSystemEntityType.file) {
        return AppImage(
          path: path,
          name: resolvedName,
          version: '${stat.modified.millisecondsSinceEpoch}:${stat.size}',
          modified: stat.modified,
          size: stat.size,
        );
      }
    } catch (_) {
      // Fall back to path-only metadata if stat fails.
    }
    return AppImage(path: path, name: resolvedName);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppImage && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
