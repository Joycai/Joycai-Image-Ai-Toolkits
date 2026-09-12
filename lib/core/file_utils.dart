import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class FileUtils {
  /// Converts user input into a single safe filename component. Separators,
  /// control characters and Windows-reserved punctuation cannot escape the
  /// configured output directory; blank or dot-only values use [fallback].
  static String safeFilenamePrefix(String raw, {String fallback = 'result'}) {
    var value = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    value = value.replaceAll(RegExp(r'[. ]+$'), '');
    if (value.isEmpty || value == '.' || value == '..') return fallback;
    return value.length > 120 ? value.substring(0, 120) : value;
  }

  /// Opens the folder containing the specified [path] in the system file explorer.
  static Future<void> openFolder(String path) async {
    final folderPath = File(path).parent.path;
    await openPath(folderPath);
  }

  /// Opens the specified [path] (file or folder) in the system file explorer or default application.
  static Future<void> openPath(String path) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else {
      // Fallback for mobile platforms
      final uri = Uri.file(path);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  /// Opens the specified [uri] in the default browser or application.
  static Future<void> openUri(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// [path] with the [from] prefix swapped for [to], or null when [path] is
  /// neither [from] itself nor inside it.
  ///
  /// The one primitive behind every "a folder was renamed or moved, fix up
  /// what pointed at it" pass — the browser's directory lists, the staging
  /// marks, the workbench's registered sources. Segment-aware: `D:\\ai_res`
  /// does not match `D:\\ai_res2`, which a bare `startsWith` would.
  static String? rebasePath(
    String path, {
    required String from,
    required String to,
  }) {
    if (p.equals(path, from)) return to;
    if (!p.isWithin(from, path)) return null;
    return p.join(to, p.relative(path, from: from));
  }
}
