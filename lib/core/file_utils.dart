import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class FileUtils {
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
}
