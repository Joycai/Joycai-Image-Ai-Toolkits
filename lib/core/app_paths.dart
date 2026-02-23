import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  static Future<String> getDataDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final supportDir = await getApplicationSupportDirectory();
      return supportDir.path;
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
    if (Platform.isAndroid || Platform.isIOS) return false;
    
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return await File(p.join(exeDir, '.portable')).exists();
  }

  static Future<void> setPortableMode(bool enabled) async {
    if (Platform.isAndroid || Platform.isIOS) return;
    
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
