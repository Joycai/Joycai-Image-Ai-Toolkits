import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/repositories/image_layer_repository.dart';
import 'folder_operations_service.dart';
import 'trash_service.dart';

/// One file that could not be removed, and why.
class FileDeleteFailure {
  final String path;
  final String message;

  const FileDeleteFailure(this.path, this.message);
}

/// How a delete run ended. A run never stops at the first failure: the user
/// picked a set, and the ones that can go should go.
class FileDeleteOutcome {
  /// Paths that are no longer on disk.
  final List<String> deleted;

  final List<FileDeleteFailure> failed;

  const FileDeleteOutcome({required this.deleted, required this.failed});

  bool get isClean => failed.isEmpty;
}

/// Deleting *files* from the browser — to the system trash, or for good.
///
/// Same shape as [FolderOperationsService], which owns the folder side and
/// whose rules this follows: trash wherever the platform has one, a permanent
/// delete only where it does not, and never one silently standing in for the
/// other.
///
/// Every refusal is re-checked here at execution time. The dialog above
/// checks the same things, but a guard that only lives in a widget is one
/// refactor away from being gone, and what is at stake is the user's files.
class FileDeleteService {
  const FileDeleteService._();

  /// Whether [delete] with `toTrash: true` is available here.
  static Future<bool> get trashSupported => TrashService.isSupported;

  /// Removes each of [paths].
  ///
  /// Asking for [toTrash] where the trash does not exist throws rather than
  /// deleting anything — the caller asked for something recoverable and must
  /// not get something else. Directories are refused per entry: this service
  /// deletes files, and a folder is [FolderOperationsService.delete]'s job,
  /// which has the inventory and the root protection the user expects to see
  /// first. [protectedRoots] is checked again for the same reason it is there.
  static Future<FileDeleteOutcome> delete(
    Iterable<String> paths, {
    required bool toTrash,
    Iterable<String> protectedRoots = const <String>{},
  }) async {
    if (toTrash && !await trashSupported) {
      throw const FileSystemException('Trash is not available on this platform');
    }

    final List<String> deleted = <String>[];
    final List<FileDeleteFailure> failed = <FileDeleteFailure>[];
    final ImageLayerRepository layers = ImageLayerRepository();

    for (final String path in paths) {
      if (FolderOperationsService.isRegisteredRoot(path, protectedRoots)) {
        failed.add(FileDeleteFailure(path, 'A registered root cannot be deleted here'));
        continue;
      }
      if (await Directory(path).exists()) {
        failed.add(FileDeleteFailure(path, 'Not a file: ${p.basename(path)}'));
        continue;
      }

      try {
        if (toTrash) {
          await TrashService.trash(path);
        } else {
          await File(path).delete();
        }
      } on FileSystemException catch (e) {
        failed.add(FileDeleteFailure(path, e.message));
        continue;
      }

      deleted.add(path);
      // Bookkeeping, never a reason the delete itself failed — the same
      // contract [ImageLayerRepository.forget] has for an overwriting copy.
      await layers.forget(path);
    }

    return FileDeleteOutcome(deleted: deleted, failed: failed);
  }
}
