import 'dart:io';

import 'package:flutter/material.dart';

/// Cross-platform file abstraction
class AppFile {
  final String path;
  final String name;

  AppFile({
    required this.path,
    required this.name,
  });

  factory AppFile.fromFile(File file) {
    return AppFile(
      path: file.path,
      name: file.path.split(Platform.pathSeparator).last,
    );
  }

  ImageProvider get imageProvider {
    return FileImage(File(path));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppFile && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
