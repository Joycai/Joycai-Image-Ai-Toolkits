import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Cross-platform file abstraction
class AppFile {
  final String path;
  final String name;
  final Uint8List? bytes; // Useful for Web or temporary memory files

  AppFile({
    required this.path,
    required this.name,
    this.bytes,
  });

  factory AppFile.fromFile(File file) {
    return AppFile(
      path: file.path,
      name: file.path.split(Platform.pathSeparator).last,
    );
  }

  ImageProvider get imageProvider {
    if (kIsWeb && bytes != null) {
      return MemoryImage(bytes!);
    }
    return FileImage(File(path));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFile && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
