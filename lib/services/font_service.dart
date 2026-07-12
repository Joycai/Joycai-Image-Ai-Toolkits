import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';

/// A single downloadable font file (one weight of a family).
class FontAsset {
  final String url;
  final String filename;

  /// Uncompressed size in bytes, used to show a download estimate and to
  /// weight progress across a multi-file download.
  final int approxBytes;

  const FontAsset({
    required this.url,
    required this.filename,
    required this.approxBytes,
  });
}

/// A font family that is not bundled with the app and must be fetched on
/// first use. The [key] doubles as the family name passed to
/// [ThemeData.fontFamily] and the [FontLoader] family name.
class DownloadableFont {
  final String key;
  final String displayName;
  final List<FontAsset> assets;

  const DownloadableFont({
    required this.key,
    required this.displayName,
    required this.assets,
  });

  int get totalBytes => assets.fold(0, (sum, a) => sum + a.approxBytes);
}

/// Downloads, caches and registers on-demand fonts at runtime.
///
/// The two CJK families offered here are ~16 MB each, so bundling them would
/// bloat every install. Instead we fetch them from a CDN the first time the
/// user picks one, cache the `.ttf` files under the app data directory, and
/// register them with a [FontLoader] so [ThemeData.fontFamily] can resolve
/// them just like the bundled NotoSansSC.
class FontService {
  FontService._();
  static final FontService instance = FontService._();

  // jsDelivr mirrors of the vendors' open-source, commercial-use-permitted
  // releases (HarmonyOS Sans / MiSans). Sizes are the authoritative blob
  // sizes reported by GitHub.
  static const Map<String, DownloadableFont> _fonts = {
    'HarmonyOSSansSC': DownloadableFont(
      key: 'HarmonyOSSansSC',
      displayName: 'HarmonyOS Sans',
      assets: [
        FontAsset(
          url:
              'https://cdn.jsdelivr.net/gh/IKKI2000/harmonyos-fonts@main/fonts/HarmonyOS_Sans_SC/HarmonyOS_Sans_SC_Regular.ttf',
          filename: 'HarmonyOS_Sans_SC_Regular.ttf',
          approxBytes: 8261128,
        ),
        FontAsset(
          url:
              'https://cdn.jsdelivr.net/gh/IKKI2000/harmonyos-fonts@main/fonts/HarmonyOS_Sans_SC/HarmonyOS_Sans_SC_Bold.ttf',
          filename: 'HarmonyOS_Sans_SC_Bold.ttf',
          approxBytes: 8158996,
        ),
      ],
    ),
    'MiSans': DownloadableFont(
      key: 'MiSans',
      displayName: 'MiSans',
      assets: [
        FontAsset(
          url:
              'https://cdn.jsdelivr.net/gh/dsrkafuu/misans@main/raw/Normal/ttf/MiSans-Regular.ttf',
          filename: 'MiSans-Regular.ttf',
          approxBytes: 8073152,
        ),
        FontAsset(
          url:
              'https://cdn.jsdelivr.net/gh/dsrkafuu/misans@main/raw/Normal/ttf/MiSans-Bold.ttf',
          filename: 'MiSans-Bold.ttf',
          approxBytes: 7959920,
        ),
      ],
    ),
  };

  /// Families already registered with the engine this session.
  final Set<String> _loaded = {};

  static bool isDownloadable(String key) => _fonts.containsKey(key);
  static DownloadableFont? meta(String key) => _fonts[key];

  Future<Directory> _fontsDir() async {
    final base = await AppPaths.getDataDirectory();
    final dir = Directory(p.join(base, 'fonts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// True when every `.ttf` for [key] is present and non-empty on disk.
  Future<bool> isDownloaded(String key) async {
    final font = _fonts[key];
    if (font == null) return false;
    final dir = await _fontsDir();
    for (final asset in font.assets) {
      final file = File(p.join(dir.path, asset.filename));
      if (!await file.exists() || await file.length() < 1024) return false;
    }
    return true;
  }

  /// Downloads all weights for [key]. [onProgress] receives a 0..1 fraction
  /// weighted by file size. Throws on any network/HTTP failure, leaving no
  /// partial file in place (writes to `.part` then renames).
  Future<void> download(String key, {void Function(double)? onProgress}) async {
    final font = _fonts[key];
    if (font == null) throw ArgumentError('Unknown font: $key');

    final dir = await _fontsDir();
    final total = font.totalBytes;
    int completedBytes = 0;

    for (final asset in font.assets) {
      final response = await http.get(Uri.parse(asset.url));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw Exception('HTTP ${response.statusCode} for ${asset.url}');
      }
      final part = File(p.join(dir.path, '${asset.filename}.part'));
      await part.writeAsBytes(response.bodyBytes, flush: true);
      await part.rename(p.join(dir.path, asset.filename));

      completedBytes += asset.approxBytes;
      onProgress?.call((completedBytes / total).clamp(0.0, 1.0));
    }

    // Force a fresh load from the newly written files.
    _loaded.remove(key);
  }

  /// Registers [key] with the engine so text can render in it. No-op if the
  /// family is already loaded this session or is not a downloadable font.
  Future<void> load(String key) async {
    if (_loaded.contains(key)) return;
    final font = _fonts[key];
    if (font == null) return;

    final dir = await _fontsDir();
    final loader = FontLoader(key);
    for (final asset in font.assets) {
      final file = File(p.join(dir.path, asset.filename));
      final bytes = await file.readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    _loaded.add(key);
  }

  /// Startup helper: silently register [key] if it is a downloadable font that
  /// is already cached, so the saved preference renders on launch.
  Future<void> ensureLoadedIfPresent(String key) async {
    if (!isDownloadable(key)) return;
    if (await isDownloaded(key)) {
      try {
        await load(key);
      } catch (_) {
        // A corrupt cache just falls back to the platform font; the user can
        // re-select to re-download.
      }
    }
  }
}
