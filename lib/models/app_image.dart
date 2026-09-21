import 'dart:io';

/// Cross-platform image abstraction
class AppImage {
  final String path;
  final String name;

  AppImage({
    required this.path,
    required this.name,
  });

  factory AppImage.fromFile(File file) {
    return AppImage(
      path: file.path,
      name: file.path.split(Platform.pathSeparator).last,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppImage && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
