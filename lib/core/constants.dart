import 'package:flutter/material.dart';

import 'theme_accent.dart';

// Image-generation aspect-ratio / resolution options are now described
// declaratively per model family in `services/llm/model_capabilities.dart`,
// since different models (nanoBanana, Imagen, OpenAI image) support different
// option sets.

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
  refiner('refiner'),
  video('video');

  final String value;
  const ModelTag(this.value);

  static ModelTag fromString(String? val) {
    return ModelTag.values.firstWhere((e) => e.value == val, orElse: () => ModelTag.chat);
  }
}

enum VeoResolution {
  r720p('720p'),
  r1080p('1080p'),
  r4k('4k');

  final String value;
  const VeoResolution(this.value);

  static VeoResolution fromString(String? val) {
    return VeoResolution.values.firstWhere((e) => e.value == val, orElse: () => VeoResolution.r720p);
  }
}

enum VeoAspectRatio {
  r9_16('9:16'),
  r16_9('16:9');

  final String value;
  const VeoAspectRatio(this.value);

  static VeoAspectRatio fromString(String? val) {
    return VeoAspectRatio.values.firstWhere((e) => e.value == val, orElse: () => VeoAspectRatio.r16_9);
  }
}

class AppConstants {
  // UI Defaults
  static const int maxConcurrency = 8;
  static const int workbenchTabCount = 6;

  // Padding, radius, opacity and font-size constants used to live here and
  // had no call sites at all — the app measured itself in literals instead.
  // Geometry now lives in `core/design_tokens.dart` (AppRadius / AppSize /
  // AppAlpha) and type sizes in the scale that `core/app_theme.dart` builds.

  /// The key of [presetThemes] the app opens with, and falls back to when a
  /// stored preference no longer names a preset.
  static const String defaultThemeAccentKey = 'Blue';

  /// The theme colours a user can pick, each as a light/dark pair.
  ///
  /// Both halves of every entry are finished colours, drawn verbatim as
  /// `primary` in their brightness (see `ThemeAccent`). Each started from
  /// `ThemeAccent.fromSeed` on the Material seed the preset is named after —
  /// same hue and chroma, tone set to 44 for light and lifted to at least 62
  /// for dark. The light halves *are* that result (`design_tokens_test` pins
  /// each to `fromSeed(seed).light`); the dark halves were then adjusted by
  /// eye on the dark ramp. Every light value
  /// carries white at ≥ 5.5:1 and reads as text on the light canvas at
  /// ≥ 4.8:1; every dark value holds ≥ 4.5:1 as text on the dark card and
  /// carries its tone-10 ink at ≥ 5.4:1. `design_tokens_test` re-measures
  /// all of it on every preset, so a retune that drifts fails there rather
  /// than in a badge nobody can read.
  ///
  /// Stored by **key**, not by hex — so a preset can be retuned in a later
  /// version and every user who picked it gets the retune.
  static const Map<String, ThemeAccent> presetThemes = {
    // The design spec's own accent, and the app's default. Kept first so the
    // swatch row opens on the colour the mockups were drawn in. The light
    // half is the spec's `#4A72E8` at tone 44 — its hue and chroma, as close
    // as white text on it allows (the spec's own value is 4.3:1). The dark
    // half is the spec's own too — frame `10b` draws its accent at `#5B8DFF`.
    'Blue': ThemeAccent(light: Color(0xFF3560D5), dark: Color(0xFF5B8DFF)),
    // A low-chroma slate (chroma 20). The vibrant palette's tone 40 pulled
    // it to a saturated `#006783`; the light half keeps the slate. The dark
    // half sits a little above (chroma ~28) so it still reads on the dark
    // card without turning into a blue.
    'BlueGrey': ThemeAccent(light: Color(0xFF4F6C7A), dark: Color(0xFF6F9DB5)),
    // Material's indigo is tone 38 and chroma 55; the palette's tone 40 was
    // `#1242FF`, an electric blue. The light half is the indigo.
    'Indigo': ThemeAccent(light: Color(0xFF4E5FC4), dark: Color(0xFF7A8DFF)),
    'Teal': ThemeAccent(light: Color(0xFF00756A), dark: Color(0xFF1FA89A)),
    // Dark lifted to 65, not 62: green's chroma peaks higher up the tone
    // scale, and at 62 it went muddy.
    'Green': ThemeAccent(light: Color(0xFF047921), dark: Color(0xFF4FB252)),
    // The one light half off tone 44: at 44 orange is a brown (`#985900`),
    // and no tone that is orange carries white text. Tone 55 is the lightest
    // that holds its own tone-10 ink at AA (4.6:1) and still stands as an
    // outline or icon on the canvas (3.3:1); text in the accent falls back
    // to the wash label there (AppAccent.accentText), so nothing reads
    // amber-on-grey at 3:1. The dark half is the seed's tone 72, a point
    // warmer.
    'Orange': ThemeAccent(light: Color(0xFFBF7100), dark: Color(0xFFF59A1A)),
    // The palette's tone 40 was `#7801FF`, a violet neon; the light half is
    // deep purple's own chroma 63.
    'DeepPurple': ThemeAccent(light: Color(0xFF7A4ECB), dark: Color(0xFFA97DFF)),
    'Rose': ThemeAccent(light: Color(0xFFCF0053), dark: Color(0xFFFF5B83)),
  };

  // Font selection. [systemFontKey] is a sentinel meaning "use the platform
  // default font"; every other key is a family name bundled in pubspec.yaml.
  // Brand names are intentionally not localized.
  static const String systemFontKey = 'system';
  static const List<({String key, String label})> fontChoices = [
    (key: systemFontKey, label: ''), // label resolved from l10n at build time
    (key: 'NotoSansSC', label: 'Noto Sans SC'),
    (key: 'HarmonyOSSansSC', label: 'HarmonyOS Sans'),
    (key: 'MiSans', label: 'MiSans'),
  ];

  /// What a tag without a colour of its own is drawn in — the Blue Grey entry
  /// of [tagColors].
  ///
  /// Named because the literal was loose in seven files, every one of them
  /// assuming the others agreed. Stored as an `int` because that is what
  /// `llm_channels.tag_color` holds and what the fallback has to compose with.
  static const int defaultTagColor = 0xFF607D8B;

  // Material 3 standard color palette for tags
  static const List<Color> tagColors = [
    // Primary colors
    Color(0xFF2196F3), // Blue
    Color(0xFFF44336), // Red
    Color(0xFF4CAF50), // Green
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFF009688), // Teal
    Color(0xFFE91E63), // Pink
    Color(0xFF3F51B5), // Indigo

    // Extended palette
    Color(0xFFFFEB3B), // Yellow
    Color(0xFF00BCD4), // Cyan
    Color(0xFF8BC34A), // Light Green
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF673AB7), // Deep Purple
    Color(0xFF03A9F4), // Light Blue
    Color(0xFFCDDC39), // Lime
    Color(0xFFFFC107), // Amber

    // Neutral tones
    Color(0xFF795548), // Brown
    Color(0xFF607D8B), // Blue Grey
    Color(0xFF9E9E9E), // Grey
    Color(0xFF455A64), // Dark Blue Grey
  ];

  static bool isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') || 
           ext.endsWith('.jpeg') || 
           ext.endsWith('.png') || 
           ext.endsWith('.gif') || 
           ext.endsWith('.webp') || 
           ext.endsWith('.bmp') ||
           ext.endsWith('.avif');
  }

  static bool isVideoFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4') || 
           ext.endsWith('.mkv') || 
           ext.endsWith('.mov') || 
           ext.endsWith('.avi') || 
           ext.endsWith('.webm');
  }

  static bool isSupportedFile(String path) {
    return isImageFile(path) || isVideoFile(path);
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
