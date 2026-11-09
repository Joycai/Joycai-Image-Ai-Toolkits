import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'portable_storage.dart';
import 'windows_package_identity.dart';
import 'windows_package_storage.dart';

class AppPaths {
  static final _portable = PortableStorage(
    isWindows: Platform.isWindows,
    identity: WindowsPackage.identity,
    executableDirectory: File(Platform.resolvedExecutable).parent.path,
  );

  /// Only confirmed unpackaged Windows processes may write beside the executable.
  static bool get supportsPortableMode => _portable.supported;

  /// Bootstrap location stays stable when a complete installation is imported.
  static bool get usesWindowsPackageStorage =>
      Platform.isWindows && WindowsPackage.identity != WindowsPackageIdentity.unpackaged;

  static bool get supportsInstallationImport => usesWindowsPackageStorage || Platform.isMacOS;

  static Future<String> getSupportDirectory() async => usesWindowsPackageStorage
      ? WindowsPackageStorage.supportDirectory()
      : (await getApplicationSupportDirectory()).path;

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
      return supportsInstallationImport ? resolveDataDirectory(support) : support;
    }

    return _portable.dataDirectory(getSupportDirectory);
  }

  static Future<String> getTempDirectory() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }

  static Future<bool> isPortableMode() => _portable.isEnabled();

  static Future<void> setPortableMode(bool enabled) => _portable.setEnabled(enabled);
}
