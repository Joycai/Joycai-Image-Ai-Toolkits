import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/versioned_file_image.dart';
import '../../models/app_image.dart';
import '../../models/browser_file.dart';

// How a file looks — its glyph and its picture. Kept out of `models/`, which
// knows what a file *is* and nothing of `Icons` or `ImageProvider`.

extension FileCategoryGlyph on FileCategory {
  IconData get icon {
    switch (this) {
      case FileCategory.image:
        return Icons.image;
      case FileCategory.video:
        return Icons.movie;
      case FileCategory.audio:
        return Icons.audiotrack;
      case FileCategory.text:
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }
}

extension BrowserFileVisuals on BrowserFile {
  IconData get icon => category.icon;

  ImageProvider get imageProvider =>
      VersionedFileImage(File(path), version: '${modified.millisecondsSinceEpoch}:$size');
}

extension AppImageVisuals on AppImage {
  ImageProvider get imageProvider => VersionedFileImage(File(path), version: version);
}
