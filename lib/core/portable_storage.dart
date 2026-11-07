import 'dart:io';

import 'package:path/path.dart' as p;

import 'windows_package_identity.dart';

/// Owns the portable marker boundary, including the final filesystem mutation.
class PortableStorage {
  PortableStorage({
    required this.isWindows,
    required this.identity,
    required this.executableDirectory,
  });

  final bool isWindows;
  final WindowsPackageIdentity identity;
  final String executableDirectory;

  bool get supported => isWindows && identity == WindowsPackageIdentity.unpackaged;
  File get _marker => File(p.join(executableDirectory, '.portable'));

  Future<bool> isEnabled() async => supported && await _marker.exists();

  Future<String> dataDirectory(Future<String> Function() supportDirectory) async =>
      await isEnabled() ? executableDirectory : await supportDirectory();

  Future<void> setEnabled(bool enabled) async {
    // Do not even delete a stale marker in a package installation.
    if (!supported) return;
    if (enabled) {
      if (!await _marker.exists()) await _marker.create();
    } else {
      if (await _marker.exists()) await _marker.delete();
    }
  }
}
