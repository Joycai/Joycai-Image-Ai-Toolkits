import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

enum WindowsPackageIdentity { packaged, unpackaged, unknown }

/// Process identity is immutable. Query the OS, not the distribution build flag:
/// a direct-distribution executable can also be installed through sideloaded MSIX.
abstract final class WindowsPackage {
  static final identity = detect();

  static WindowsPackageIdentity detect({int Function()? query}) {
    if (query == null && !Platform.isWindows) return WindowsPackageIdentity.unknown;
    try {
      return switch ((query ?? _query)()) {
        122 => WindowsPackageIdentity.packaged, // ERROR_INSUFFICIENT_BUFFER
        15700 => WindowsPackageIdentity.unpackaged, // APPMODEL_ERROR_NO_PACKAGE
        _ => WindowsPackageIdentity.unknown,
      };
    } catch (_) {
      // Unknown identity must never authorize writes beside the executable.
      return WindowsPackageIdentity.unknown;
    }
  }

  static int _query() {
    final getName = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
          int Function(Pointer<Uint32>, Pointer<Utf16>)
        >('GetCurrentPackageFullName');
    final length = calloc<Uint32>();
    try {
      return getName(length, nullptr);
    } finally {
      calloc.free(length);
    }
  }
}
