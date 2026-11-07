import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Explicit package-local storage avoids the merged view of legacy AppData.
abstract final class WindowsPackageStorage {
  static const channel = MethodChannel('joycai/windows_store');

  static Future<String> supportDirectory() async {
    final path = await channel.invokeMethod<String>('dataPath');
    if (path == null || !p.isAbsolute(path)) {
      throw StateError('Package storage unavailable');
    }
    await Directory(path).create(recursive: true);
    return path;
  }
}
