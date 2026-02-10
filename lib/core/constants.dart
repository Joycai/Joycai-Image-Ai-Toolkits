import 'package:flutter/material.dart';

enum AppAspectRatio {
  notSet('not_set'),
  r1_1('1:1'),
  r2_3('2:3'),
  r3_2('3:2'),
  r3_4('3:4'),
  r4_3('4:3'),
  r4_5('4:5'),
  r5_4('5:4'),
  r9_16('9:16'),
  r16_9('16:9');

  final String value;
  const AppAspectRatio(this.value);

  static AppAspectRatio fromString(String? val) {
    return AppAspectRatio.values.firstWhere((e) => e.value == val, orElse: () => AppAspectRatio.notSet);
  }
}

enum AppResolution {
  r1K('1K'),
  r2K('2K'),
  r4K('4K');

  final String value;
  const AppResolution(this.value);

  static AppResolution fromString(String? val) {
    return AppResolution.values.firstWhere((e) => e.value == val, orElse: () => AppResolution.r1K);
  }
}

enum BillingMode {
  token('token'),
  request('request');

  final String value;
  const BillingMode(this.value);

  static BillingMode fromString(String? val) {
    return BillingMode.values.firstWhere((e) => e.value == val, orElse: () => BillingMode.token);
  }
}

enum ModelTag {
  image('image'),
  multimodal('multimodal'),
  chat('chat'),
  refiner('refiner');

  final String value;
  const ModelTag(this.value);

  static ModelTag fromString(String? val) {
    return ModelTag.values.firstWhere((e) => e.value == val, orElse: () => ModelTag.chat);
  }
}

class AppConstants {
  // UI Defaults
  static const double defaultThumbnailSize = 150.0;
  static const int maxConcurrency = 8;
  static const Duration animationDuration = Duration(milliseconds: 200);

  // Opacity levels
  static const double opacityLow = 0.05;
  static const double opacityMedium = 0.3;
  static const double opacityHigh = 0.5;

  // UI Layout Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double cardRadius = 12.0;
  static const double smallRadius = 8.0;
  static const double inputFontSize = 13.0;
  static const double smallFontSize = 11.0;
  
  static const double minThumbnailSize = 80.0;
  static const double maxThumbnailSize = 400.0;

  static const Map<String, Color> presetThemes = {
    'BlueGrey': Colors.blueGrey,
    'Indigo': Colors.indigo,
    'Teal': Colors.teal,
    'Green': Colors.green,
    'Orange': Colors.orange,
    'DeepPurple': Colors.deepPurple,
    'Rose': Colors.pink,
  };

  static const List<Color> tagColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
    Colors.blueGrey,
  ];

  static bool isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') || 
           ext.endsWith('.jpeg') || 
           ext.endsWith('.png') || 
           ext.endsWith('.webp') || 
           ext.endsWith('.bmp');
  }

  static String formatAspectRatio(int width, int height) {
    if (width == 0 || height == 0) return "";
    final double ratio = width / height;
    
    // Standard ratios and their decimal values
    final Map<String, double> standardRatios = {
      '1:1': 1.0,
      '2:3': 2/3,
      '3:2': 3/2,
      '4:3': 4/3,
      '3:4': 3/4,
      '5:4': 1.25,
      '4:5': 0.8,
      '16:9': 16/9,
      '9:16': 9/16,
      '21:9': 21/9,
    };

    String? bestMatch;
    double minDiff = 0.02; // Threshold for "closeness"

    for (var entry in standardRatios.entries) {
      final diff = (ratio - entry.value).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestMatch = entry.key;
      }
    }

    if (bestMatch != null) {
      return bestMatch;
    }

    // If no match found, return the numeric ratio
    return ratio.toStringAsFixed(2);
  }

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB", "TB"];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(size < 10 ? 2 : 1)} ${units[i]}";
  }

  static String getMimeType(String path) {
    final ext = path.toLowerCase();
    if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) return 'image/jpeg';
    if (ext.endsWith('.png')) return 'image/png';
    if (ext.endsWith('.gif')) return 'image/gif';
    if (ext.endsWith('.webp')) return 'image/webp';
    if (ext.endsWith('.bmp')) return 'image/bmp';
    if (ext.endsWith('.mp4')) return 'video/mp4';
    if (ext.endsWith('.mp3')) return 'audio/mpeg';
    if (ext.endsWith('.txt')) return 'text/plain';
    if (ext.endsWith('.md')) return 'text/markdown';
    if (ext.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }
}
