import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_transfer_service.dart';
import 'trash_service.dart';

/// Why a folder name cannot be used. First match wins, in this order.
enum FolderNameError {
  empty,
  illegalChars,
  reservedName,

  /// A folder or file of that name is already in the parent.
  exists,

  /// The resulting path is already one of the browser's registered roots or
  /// active directories — the tree must never show one path twice.
  registered,
}

/// Why a folder cannot be dropped where the user is pointing.
enum FolderMoveRejection {
  /// Registered roots stay where they are; the tree's "remove from list" is
  /// how a root changes.
  isRoot,
  intoSelf,
  intoDescendant,

  /// Already in that folder — a move would be a no-op.
  sameParent,

  /// The destination holds an entry of that name. Not merged: merging is a
  /// per-file conflict pass, which is the staging area's job.
  targetExists,
}

/// Which way a folder transfer goes.
enum FolderTransferMode { move, copy }

/// What is inside a folder, for the delete confirmation.
class FolderInventory {
  final int folders;
  final int files;
  final int bytes;

  const FolderInventory({required this.folders, required this.files, required this.bytes});

  int get items => folders + files;

  bool get isEmpty => items == 0;
}

/// How a folder transfer ended.
class FolderTransferOutcome {
  /// Where the folder now is (or would be).
  final String targetPath;

  /// True when the copy route ran — a cross-volume move, or any copy.
  /// A same-volume move is one rename and reports 0 / 0 items.
  final bool copied;

  final bool cancelled;

  /// Files and symbolic links that reached the destination before the run ended.
  final int filesDone;
  final int filesTotal;

  /// Set when the destination is complete but the source could not be
  /// removed, so the folder now exists twice.
  final String? failure;

  const FolderTransferOutcome({
    required this.targetPath,
    required this.copied,
    required this.cancelled,
    required this.filesDone,
    required this.filesTotal,
    this.failure,
  });

  bool get isClean => !cancelled && failure == null;
}

/// Folder management behind the file browser's directory tree: create,
/// rename, delete, move. Pure IO plus validation; nothing here knows about
/// widgets or state.
///
/// Same shape as [FileTransferService] — static, throws [FileSystemException]
/// on disk failures, and guards every destructive step at execution time
/// rather than trusting an earlier check.
class FolderOperationsService {
  const FolderOperationsService._();

  static const String _windowsIllegal = r'<>:"/\|?*';
  static const String _posixIllegal = r'/\';

  static const Set<String> _windowsReserved = {
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// The characters a name may not contain on this platform, for the error
  /// message. Backslash is refused everywhere: legal on POSIX, but a name the
  /// user will one day sync to a Windows disk.
  static String illegalChars({bool? windows}) =>
      (windows ?? Platform.isWindows) ? _windowsIllegal : _posixIllegal;

  /// Trims, and on Windows drops the trailing dots and spaces the shell would
  /// silently strip anyway. Applied before validation so the user is not told
  /// off for something the disk would have fixed.
  static String sanitize(String name, {bool? windows}) {
    var out = name.trim();
    if (windows ?? Platform.isWindows) {
      out = out.replaceAll(RegExp(r'[. ]+$'), '');
    }
    return out;
  }

  /// Checks [name] as a new child of [parent], or as the new name of
  /// [currentPath] when renaming.
  ///
  /// Null means usable. Renaming to the same name (any case, on the
  /// case-insensitive platforms) is *not* an error; the caller treats it as
  /// "nothing to do".
  static FolderNameError? validateName({
    required String parent,
    required String name,
    String? currentPath,
    Set<String> registered = const {},
    bool? windows,
  }) {
    final isWindows = windows ?? Platform.isWindows;
    final clean = sanitize(name, windows: isWindows);
    if (clean.isEmpty) return FolderNameError.empty;

    final illegal = illegalChars(windows: isWindows);
    for (final rune in clean.runes) {
      if (rune < 0x20 || illegal.contains(String.fromCharCode(rune))) {
        return FolderNameError.illegalChars;
      }
    }

    if (isWindows) {
      final stem = clean.split('.').first.toUpperCase();
      if (_windowsReserved.contains(stem)) return FolderNameError.reservedName;
    }

    final candidate = p.join(parent, clean);
    final unchanged = currentPath != null && _sameName(candidate, currentPath);
    if (unchanged) return null;

    if (registered.any((r) => p.equals(r, candidate))) {
      return FolderNameError.registered;
    }

    if (_entryExists(parent, clean)) return FolderNameError.exists;
    return null;
  }

  /// Whether [parent] already holds an entry called [name], compared the way
  /// the disk compares — case-insensitively on Windows and macOS.
  static bool _entryExists(String parent, String name) {
    final direct = p.join(parent, name);
    if (_pathExists(direct)) return true;
    if (!_caseInsensitiveFs) return false;
    try {
      final lower = name.toLowerCase();
      return Directory(parent)
          .listSync(followLinks: false)
          .any((e) => p.basename(e.path).toLowerCase() == lower);
    } on FileSystemException {
      return false;
    }
  }

  static bool get _caseInsensitiveFs => Platform.isWindows || Platform.isMacOS;

  static bool _pathExists(String path) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.notFound;
    } on FileSystemException {
      // An unreadable target is not safe to replace.
      return true;
    }
  }

  static bool _sameName(String a, String b) {
    if (p.equals(a, b)) return true;
    return _caseInsensitiveFs && p.basename(a).toLowerCase() == p.basename(b).toLowerCase() &&
        p.equals(p.dirname(a), p.dirname(b));
  }

  /// Counts what [path] holds, off the UI isolate.
  static Future<FolderInventory> inventory(String path) => compute(_inventoryIsolate, path);

  static FolderInventory _inventoryIsolate(String path) {
    var folders = 0;
    var files = 0;
    var bytes = 0;
    try {
      for (final entity in Directory(path).listSync(recursive: true, followLinks: false)) {
        if (entity is Directory) {
          folders++;
        } else if (entity is File) {
          files++;
          try {
            bytes += entity.lengthSync();
          } on FileSystemException {
            // Counted, just not weighed.
          }
        } else if (entity is Link) {
          // A link is still an item the delete confirmation must disclose.
          // Never follow it: deleting this tree removes the link, not its target.
          files++;
        }
      }
    } on FileSystemException {
      // Unreadable subtrees report what was seen before the failure.
    }
    return FolderInventory(folders: folders, files: files, bytes: bytes);
  }

  /// Creates `parent/name` and returns its path. [name] is sanitised first.
  static Future<String> create(String parent, String name) async {
    final target = p.join(parent, sanitize(name));
    await Directory(target).create();
    return target;
  }

  /// Renames the folder at [path] in place and returns the new path.
  static Future<String> rename(String path, String newName) async {
    final target = p.join(p.dirname(path), sanitize(newName));
    if (p.equals(target, path)) return path;
    final renamed = await Directory(path).rename(target);
    return renamed.path;
  }

  /// Whether [delete] with `toTrash: true` is available here.
  static Future<bool> get trashSupported => TrashService.isSupported;

  /// Removes the folder at [path] — to the system trash, or for good.
  ///
  /// [toTrash] is only honoured where [trashSupported] is true; asking for it
  /// elsewhere throws rather than quietly deleting forever.
  /// [protectedRoots] is checked again here so a stale or incorrectly nested
  /// tree row cannot physically delete a registered root.
  static Future<void> delete(
    String path, {
    required bool toTrash,
    Iterable<String> protectedRoots = const {},
  }) async {
    if (isRegisteredRoot(path, protectedRoots)) {
      throw FileSystemException('A registered root can only be removed from the list', path);
    }
    if (toTrash) {
      if (!await trashSupported) {
        throw FileSystemException('Trash is not available on this platform', path);
      }
      await TrashService.trash(path);
      return;
    }
    await Directory(path).delete(recursive: true);
  }

  /// Whether [path] is one of the browser's registered roots.
  ///
  /// Registration follows the path, not the row's position in the tree: an
  /// overlapping root can also appear as a child beneath another root.
  static bool isRegisteredRoot(String path, Iterable<String> roots) =>
      roots.any((root) => p.equals(root, path));

  /// Why [source] cannot go into [destination], or null when it can.
  ///
  /// [roots] are the browser's registered directories, which refuse to be
  /// moved (but may be copied).
  static FolderMoveRejection? canTransfer(
    String source,
    String destination, {
    Set<String> roots = const {},
    FolderTransferMode mode = FolderTransferMode.move,
  }) {
    final moving = mode == FolderTransferMode.move;
    if (moving && isRegisteredRoot(source, roots)) return FolderMoveRejection.isRoot;
    if (p.equals(source, destination)) return FolderMoveRejection.intoSelf;
    if (p.isWithin(source, destination)) return FolderMoveRejection.intoDescendant;
    if (moving && p.equals(p.dirname(source), destination)) return FolderMoveRejection.sameParent;
    final target = p.join(destination, p.basename(source));
    if (_pathExists(target)) {
      return FolderMoveRejection.targetExists;
    }
    return null;
  }

  /// Moves or copies the folder at [source] into [destination].
  ///
  /// A move tries one rename first, which is instant and reports no progress.
  /// When that fails — a different volume, almost always — or for any copy,
  /// the tree is walked file by file with [onProgress] reporting bytes, and
  /// [isCancelled] consulted between files.
  ///
  /// The copy route deletes the source only after *every* file has arrived,
  /// so a cancel at any point leaves the source whole. What was already
  /// copied stays in the destination; the outcome says how much, and the
  /// tidy-up is the user's — they may well want it.
  static Future<FolderTransferOutcome> transfer(
    String source,
    String destination, {
    required FolderTransferMode mode,
    void Function(FileTransferProgress)? onProgress,
    bool Function()? isCancelled,

    /// Skip the rename attempt and take the copy route on a move. A test
    /// seam, for the same reason [FileTransferService.execute] has one: the
    /// route that deletes a whole tree cannot go unexercised, and one machine
    /// cannot arrange a cross-volume rename failure.
    @visibleForTesting bool forceCopyDelete = false,
  }) async {
    final target = p.join(destination, p.basename(source));

    // Re-checked at execution, not just at the drop: the plan-time answer
    // can go stale while a dialog is open.
    if (p.equals(source, target) || p.isWithin(source, target)) {
      throw FileSystemException('Cannot move a folder into itself', source);
    }
    if (_pathExists(target)) {
      throw FileSystemException('The destination already has an entry of this name', target);
    }

    if (mode == FolderTransferMode.move && !forceCopyDelete) {
      try {
        await Directory(source).rename(target);
        return FolderTransferOutcome(
          targetPath: target,
          copied: false,
          cancelled: false,
          filesDone: 0,
          filesTotal: 0,
        );
      } on FileSystemException {
        // Cross-device, nearly always. Caught broadly for the same reason
        // FileTransferService does: the codes differ per platform, and a real
        // permission failure fails the copy below and is reported from there.
      }
    }

    // Walk first, so the progress readout has a denominator.
    final files = <File>[];
    final dirs = <Directory>[];
    final links = <Link>[];
    var bytesTotal = 0;
    await for (final entity in Directory(source).list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        dirs.add(entity);
      } else if (entity is File) {
        files.add(entity);
        try {
          bytesTotal += await entity.length();
        } on FileSystemException {
          // Unweighed, still copied.
        }
      } else if (entity is Link) {
        // Preserve the link itself. Following it could copy data outside the
        // selected tree; ignoring it would lose the link when a move deletes
        // the source after the copy completes.
        links.add(entity);
      }
    }

    await Directory(target).create(recursive: true);
    // Shallow before deep, so a parent exists before its children are made.
    dirs.sort((a, b) => a.path.length.compareTo(b.path.length));
    for (final dir in dirs) {
      await Directory(p.join(target, p.relative(dir.path, from: source))).create(recursive: true);
    }

    final entries = <FileSystemEntity>[...links, ...files];
    var bytesDone = 0;
    var done = 0;
    for (final entity in entries) {
      if (isCancelled?.call() ?? false) {
        onProgress?.call(FileTransferProgress(
          index: done,
          total: entries.length,
          name: '',
          bytesDone: bytesDone,
          bytesTotal: bytesTotal,
        ));
        return FolderTransferOutcome(
          targetPath: target,
          copied: true,
          cancelled: true,
          filesDone: done,
          filesTotal: entries.length,
        );
      }

      final relative = p.relative(entity.path, from: source);
      onProgress?.call(FileTransferProgress(
        index: done,
        total: entries.length,
        name: relative,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      ));

      final targetPath = p.join(target, relative);
      if (entity is Link) {
        await Link(targetPath).create(await entity.target());
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
      done++;
      if (entity is File) {
        try {
          bytesDone += await entity.length();
        } on FileSystemException {
          // Same file that was unweighed above.
        }
      }
    }

    onProgress?.call(FileTransferProgress(
      index: done,
      total: entries.length,
      name: '',
      bytesDone: bytesDone,
      bytesTotal: bytesTotal,
    ));

    String? failure;
    if (mode == FolderTransferMode.move) {
      try {
        await Directory(source).delete(recursive: true);
      } on FileSystemException catch (e) {
        failure = 'Copied to $target, but the original could not be removed: ${e.message}';
      }
    }

    return FolderTransferOutcome(
      targetPath: target,
      copied: true,
      cancelled: false,
      filesDone: done,
      filesTotal: entries.length,
      failure: failure,
    );
  }

  /// Whether a move between these two would take the slow route. A hint for
  /// the UI, with the same caveats as [FileTransferService.isLikelyCrossVolume].
  static bool isLikelyCrossVolume(String source, String destination) =>
      FileTransferService.isLikelyCrossVolume(source, destination);
}
