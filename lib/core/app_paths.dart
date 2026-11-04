import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_distribution.dart';

class AppPaths {
  /// Only Windows may keep app data beside the executable.
  static bool get supportsPortableMode => Platform.isWindows;

  /// Bootstrap location stays stable when a complete installation is imported.
  static Future<String> getSupportDirectory() async =>
      (await getApplicationSupportDirectory()).path;

  /// A macOS import is activated by one atomic pointer replacement. Older
  /// installations remain intact, including their database WAL and owned media.
  static Future<String> resolveDataDirectory(String support) async {
    final pointer = File(p.join(support, 'active-installation'));
    if (!await pointer.exists()) return support;
    final id = (await pointer.readAsString()).trim();
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('Invalid active installation');
    }
    final root = Directory(p.join(support, 'installations', id));
    final canonicalSupport = await Directory(support).resolveSymbolicLinks();
    if (!p.isWithin(canonicalSupport, await root.resolveSymbolicLinks()) ||
        !await File(p.join(root.path, 'joycai_workbench.db')).exists()) {
      throw const FormatException('Active installation is unavailable');
    }
    return root.path;
  }

  static Future<String> getDataDirectory() async {
    if (!supportsPortableMode) {
      final support = await getSupportDirectory();
      return Platform.isMacOS && !AppDistribution.direct ? resolveDataDirectory(support) : support;
    }

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final portableMarker = File(p.join(exeDir, '.portable'));

    if (await portableMarker.exists()) {
      return exeDir;
    }

    final supportDir = await getApplicationSupportDirectory();
    return supportDir.path;
  }

  static Future<String> getTempDirectory() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  static Future<bool> isPortableMode() async {
    if (!supportsPortableMode) return false;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return File(p.join(exeDir, '.portable')).exists();
  }

  static Future<void> setPortableMode(bool enabled) async {
    if (!supportsPortableMode) return;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final portableMarker = File(p.join(exeDir, '.portable'));

    if (enabled) {
      if (!await portableMarker.exists()) {
        await portableMarker.create();
      }
    } else {
      if (await portableMarker.exists()) {
        await portableMarker.delete();
      }
    }
  }
}
