import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum FileCategory {
  all,
  image,
  video,
  audio,
  text,
  other,
}

extension FileCategoryExtension on FileCategory {
  IconData get icon {
    switch (this) {
      case FileCategory.image: return Icons.image;
      case FileCategory.video: return Icons.movie;
      case FileCategory.audio: return Icons.audiotrack;
      case FileCategory.text: return Icons.description;
      default: return Icons.insert_drive_file;
    }
  }

  Color get color {
    switch (this) {
      case FileCategory.image: return Colors.blue;
      case FileCategory.video: return Colors.red;
      case FileCategory.audio: return Colors.green;
      case FileCategory.text: return Colors.orange;
      default: return Colors.grey;
    }
  }
}

class BrowserFile {
  final String path;
  final String name;
  final FileCategory category;
  final int size;
  final DateTime modified;

  BrowserFile({
    required this.path,
    required this.name,
    required this.category,
    required this.size,
    required this.modified,
  });

  IconData get icon => category.icon;
  Color get color => category.color;

  /// The category an extension puts a file in, without touching the disk.
  ///
  /// Split out of [fromFile] so a path with no file behind it can still be
  /// classified — which is what the staging area needs when it restores a
  /// mark whose file has since been moved away.
  static FileCategory categoryOf(String path) {
    final ext = p.extension(path).toLowerCase();

    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'].contains(ext)) {
      return FileCategory.image;
    } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm'].contains(ext)) {
      return FileCategory.video;
    } else if (['.mp3', '.wav', '.flac', '.m4a', '.ogg', '.aac'].contains(ext)) {
      return FileCategory.audio;
    } else if (['.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.srt', '.ass', '.vtt'].contains(ext)) {
      return FileCategory.text;
    }
    return FileCategory.other;
  }

  factory BrowserFile.fromFile(File file) {
    final path = file.path;
    final stat = file.statSync();
    return BrowserFile(
      path: path,
      name: p.basename(path),
      category: categoryOf(path),
      size: stat.size,
      modified: stat.modified,
    );
  }

  /// A file known only by its path — no size, no timestamp.
  ///
  /// For entries restored from persistence, where the disk is consulted
  /// afterwards and may report the file gone. Zero size and the epoch are the
  /// honest answers to "how big, how recent" when nothing has been read yet;
  /// callers show such an entry as pending or missing rather than as a 0-byte
  /// file from 1970.
  factory BrowserFile.unresolved(String path) => BrowserFile(
        path: path,
        name: p.basename(path),
        category: categoryOf(path),
        size: 0,
        modified: DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory BrowserFile.fromMap(Map<String, dynamic> map) {
    return BrowserFile(
      path: map['path'] as String,
      name: map['name'] as String,
      category: FileCategory.values[map['categoryIndex'] as int],
      size: map['size'] as int,
      modified: DateTime.fromMillisecondsSinceEpoch(map['modified'] as int),
    );
  }

  ImageProvider get imageProvider => FileImage(File(path));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrowserFile && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
