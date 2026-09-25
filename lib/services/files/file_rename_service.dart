import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database_service.dart';
import '../db/repositories/image_layer_repository.dart';

/// Renames one file in place and carries its layer rows along — the
/// file-level twin of `FolderOperationsService.rename`.
///
/// Lifted out of the rename dialog so the dialog collects a name and reports,
/// and the rule that a rename moves the file's `image_layers` rows lives in
/// one place with the folder rule.
class FileRenameService {
  const FileRenameService._();

  /// Renames [path] to `dirname(path)/newName` and returns the new path.
  ///
  /// Throws what [File.rename] throws; the layer rows move only once the file
  /// has. [database] is for tests — production leaves it to the singleton, as
  /// every state class does.
  static Future<String> rename(String path, String newName, {DatabaseService? database}) async {
    final target = p.join(p.dirname(path), newName);
    final renamed = await File(path).rename(target);
    await ImageLayerRepository(db: database).move(path, renamed.path);
    return renamed.path;
  }
}
