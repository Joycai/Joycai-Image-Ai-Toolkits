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

  factory BrowserFile.fromFile(File file) {
    final path = file.path;
    final name = p.basename(path);
    final ext = p.extension(path).toLowerCase();
    
    FileCategory category = FileCategory.other;
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.avif'].contains(ext)) {
      category = FileCategory.image;
    } else if (['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm'].contains(ext)) {
      category = FileCategory.video;
    } else if (['.mp3', '.wav', '.flac', '.m4a', '.ogg', '.aac'].contains(ext)) {
      category = FileCategory.audio;
    } else if (['.txt', '.md', '.json', '.xml', '.yaml', '.yml', '.srt', '.ass', '.vtt'].contains(ext)) {
      category = FileCategory.text;
    }

    final stat = file.statSync();
    return BrowserFile(
      path: path,
      name: name,
      category: category,
      size: stat.size,
      modified: stat.modified,
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
