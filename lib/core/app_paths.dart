import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  static Future<String> getDataDirectory() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final portableMarker = File(p.join(exeDir, '.portable'));

    if (await portableMarker.exists()) {
      return exeDir;
    }

    final supportDir = await getApplicationSupportDirectory();
    return supportDir.path;
  }

  static Future<bool> isPortableMode() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return await File(p.join(exeDir, '.portable')).exists();
  }

  static Future<void> setPortableMode(bool enabled) async {
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
