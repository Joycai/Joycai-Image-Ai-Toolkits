import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

/// Moves a folder or file to the system's recycle bin / trash.
///
/// Dart has no portable trash call, so this is three platform glue paths
/// behind one door:
///
/// * **Windows** — `SHFileOperationW` with `FOF_ALLOWUNDO`, through the
///   `win32` bindings. No runner code involved.
/// * **macOS** — a `MethodChannel` to `FileManager.trashItem`, registered in
///   `MainFlutterWindow.swift`. The sandbox will not let anything else touch
///   `~/.Trash`.
/// * **Linux** — `gio trash`, which speaks the freedesktop trash spec for
///   whatever desktop is running. No `gio` means no trash.
///
/// Support is probed once per process, not per call: the delete dialog has to
/// know *before* it opens whether to say "move to trash" or "delete forever",
/// and finding out by trying would show the wrong words first.
class TrashService {
  TrashService._();

  static const MethodChannel _channel = MethodChannel('joycai/trash');

  static Future<bool>? _probe;

  /// Whether [trash] can work on this machine. Memoised on first read.
  static Future<bool> get isSupported => _probe ??= _detect();

  /// Test seam: forces the answer without touching the platform.
  @visibleForTesting
  static void overrideSupport(bool? supported) {
    _probe = supported == null ? null : Future.value(supported);
  }

  /// Test seam: stands in for the platform call itself, so a test can make
  /// the trash refuse without a real bin and without `gio` on the runner.
  /// Null everywhere but in a test — the real call is the only thing that
  /// can put a file somewhere the user can get it back from.
  @visibleForTesting
  static Future<void> Function(String path)? overrideTrash;

  static Future<bool> _detect() async {
    if (kIsWeb) return false;
    if (Platform.isWindows) return true;
    if (Platform.isMacOS) {
      try {
        return await _channel.invokeMethod<bool>('isSupported') ?? false;
      } on MissingPluginException {
        return false;
      } on PlatformException {
        return false;
      }
    }
    if (Platform.isLinux) {
      try {
        final result = await Process.run('gio', const ['--version']);
        return result.exitCode == 0;
      } on ProcessException {
        return false;
      }
    }
    return false;
  }

  /// Sends [path] to the trash. Throws a [FileSystemException] when the
  /// platform refused — a permission problem, a network share, a volume with
  /// no recycle bin. Never falls back to a permanent delete: the caller asked
  /// for something recoverable and must not get something else.
  static Future<void> trash(String path) async {
    final Future<void> Function(String path)? stub = overrideTrash;
    if (stub != null) return stub(path);
    if (Platform.isWindows) {
      // Off the UI isolate: the shell call is synchronous and, for a large
      // tree, not quick.
      final error = await Isolate.run(() => _trashWindows(path));
      if (error != null) throw FileSystemException(error, path);
      return;
    }
    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod<void>('trash', {'path': path});
      } on PlatformException catch (e) {
        throw FileSystemException(e.message ?? e.code, path);
      } on MissingPluginException {
        throw FileSystemException('Trash is not available in this build', path);
      }
      return;
    }
    if (Platform.isLinux) {
      final result = await Process.run('gio', ['trash', path]);
      if (result.exitCode != 0) {
        throw FileSystemException(result.stderr.toString().trim(), path);
      }
      return;
    }
    throw FileSystemException('Trash is not supported on this platform', path);
  }

  /// Returns an error message, or null on success.
  static String? _trashWindows(String path) {
    return using((arena) {
      // SHFileOperation wants a double-NUL-terminated list; `toNativeUtf16`
      // adds one terminator, the literal adds the other.
      final from = '$path\u0000'.toNativeUtf16(allocator: arena);
      final op = arena<SHFILEOPSTRUCT>();
      op.ref
        ..wFunc = FO_DELETE
        ..pFrom = PWSTR(from)
        ..pTo = PWSTR(nullptr)
        ..fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI;

      final result = SHFileOperation(op);
      if (result.value != 0) {
        return 'SHFileOperation failed (0x${result.value.toRadixString(16)})';
      }
      if (op.ref.fAnyOperationsAborted) {
        return 'The shell aborted the operation';
      }
      return null;
    });
  }
}
