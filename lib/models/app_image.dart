import 'dart:io';

/// Cross-platform image abstraction
class AppImage {
  final String path;
  final String name;

  /// Scanned modification time and size; empty before a file has been scanned.
  /// Selection identity stays path-based across edits.
  final String version;

  AppImage({required this.path, required this.name, this.version = ''});

  factory AppImage.fromFile(File file, {String version = ''}) {
    return AppImage(
      path: file.path,
      name: file.path.split(Platform.pathSeparator).last,
      version: version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppImage && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
