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
  /// not get something else. That is the **only** exception this ever throws:
  /// whatever one path does on the way out is recorded against that path, so
  /// one bad entry can neither abort the batch nor escape a caller that
  /// catches this one case.
  ///
  /// Directories are refused per entry: this service deletes files, and a
  /// folder is [FolderOperationsService.delete]'s job, which has the
  /// inventory and the root protection the user expects to see first.
  /// [protectedRoots] is checked again for the same reason it is there.
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
      try {
        if (await Directory(path).exists()) {
          failed.add(FileDeleteFailure(path, 'Not a file: ${p.basename(path)}'));
          continue;
        }
        if (toTrash) {
          await TrashService.trash(path);
        } else {
          await File(path).delete();
        }
      } on FileSystemException catch (e) {
        failed.add(FileDeleteFailure(path, e.message));
        continue;
      } on Exception catch (e) {
        // Not every way this fails is a [FileSystemException]: the trash is
        // three platform glue paths and the Linux one shells out to `gio`,
        // which throws a [ProcessException] when the binary is no longer
        // there — the support probe answered once, at startup. One entry's
        // mishap has to stay one entry's failure; out of the loop it would
        // abort the rest of the batch and reach a caller that is promised
        // only the one exception below, so the user would see nothing happen
        // and nothing said.
        failed.add(FileDeleteFailure(path, '$e'));
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
