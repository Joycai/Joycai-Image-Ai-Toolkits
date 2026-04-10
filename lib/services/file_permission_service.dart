import 'dart:io';

import 'package:file_picker/file_picker.dart';

class FilePermissionService {
  static final FilePermissionService _instance = FilePermissionService._internal();
  factory FilePermissionService() => _instance;
  FilePermissionService._internal();

  /// Checks if a path is unreachable due to OS permissions or missing directory.
  /// On macOS Sandbox, existsSync() can be true while listSync() throws.
  bool isPathUnreachable(String? path) {
    if (path == null || path.isEmpty) return false;
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return true;
      // Trigger a real OS read operation to check sandbox permissions
      dir.listSync(); 
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Triggers a system dialog to let the user re-select and authorize a folder.
  Future<String?> reAuthorize(String initialPath, {String? title}) async {
    return await FilePicker.getDirectoryPath(
      initialDirectory: initialPath,
      dialogTitle: title ?? (Platform.isMacOS 
          ? "Re-authorize access to folder" 
          : "Re-select missing folder"),
    );
  }

  /// Platform-aware error message for unreachable paths
  String getPermissionErrorMessage() {
    if (Platform.isMacOS) {
      return "macOS Permission Required";
    }
    return "Folder Access Denied";
  }

  /// Platform-aware detailed instruction
  String getPermissionInstructions() {
    if (Platform.isMacOS) {
      return "Access to this folder was denied by the OS after restart.\nPlease click the button below to re-authorize.";
    }
    return "The saved path is no longer accessible or has been moved.\nPlease re-select the folder.";
  }

  /// Platform-aware button label
  String getReAuthorizeButtonLabel() {
    if (Platform.isMacOS) {
      return "Re-authorize Access";
    }
    return "Re-select Folder";
  }
}
