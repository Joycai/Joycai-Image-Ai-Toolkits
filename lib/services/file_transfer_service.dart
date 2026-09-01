import 'dart:io';

import 'package:path/path.dart' as p;

/// Which way a staged file travels.
enum FileTransferMode { move, copy }

/// Why a staged file cannot simply be written to the destination.
///
/// One value per entry, first match in the order below wins — a source that is
/// gone is not also "already there".
enum FileTransferConflict {
  none,

  /// The source is no longer on disk. Staging holds a *mark*, not a lock, so
  /// anything can happen to the file between staging it and pasting it.
  sourceMissing,

  /// The source already sits in the destination folder. A move here is a
  /// no-op; a copy is a deliberate duplicate.
  sameLocation,

  /// Two staged files would land on the same name. Detected before
  /// [targetExists] because neither is at the target yet — the collision is
  /// between the two of them, and skipping one resolves it.
  duplicateInBatch,

  /// The destination folder already holds a file of this name.
  targetExists,
}

/// What to do about a [FileTransferConflict].
///
/// A conflicted entry with no resolution is skipped: the destructive reading
/// (overwrite) has to be asked for, never defaulted into.
enum FileConflictResolution { skip, overwrite, rename }

/// One file's place in a [FileTransferPlan].
class FileTransferEntry {
  final String sourcePath;

  /// Basename at plan time — what the destination file is called unless the
  /// entry is resolved with [FileConflictResolution.rename].
  final String name;

  /// Size in bytes, 0 when the source could not be measured. Drives the
  /// progress readout, not the transfer itself.
  final int size;

  /// Where this lands if nothing is resolved.
  final String targetPath;

  final FileTransferConflict conflict;

  /// Whether source and destination look like different volumes. See
  /// [FileTransferService.isLikelyCrossVolume] for what "look like" covers.
  final bool crossVolume;

  const FileTransferEntry({
    required this.sourcePath,
    required this.name,
    required this.size,
    required this.targetPath,
    required this.conflict,
    required this.crossVolume,
  });

  bool get hasConflict => conflict != FileTransferConflict.none;
}

/// A whole paste, resolved against the disk but not yet performed.
///
/// Planning is separate from executing so the conflicts can be shown and
/// decided before anything is written. A plan is a *snapshot*, though: the
/// disk can change while the user looks at it, which is why
/// [FileTransferService.execute] guards every destructive step again rather
/// than trusting the plan's verdicts.
class FileTransferPlan {
  final FileTransferMode mode;
  final String destination;

  /// False when the destination folder is gone. Every entry would fail; the
  /// caller is meant to refuse the paste rather than collect N identical
  /// errors.
  final bool destinationExists;

  final List<FileTransferEntry> entries;

  const FileTransferPlan({
    required this.mode,
    required this.destination,
    required this.destinationExists,
    required this.entries,
  });

  Iterable<FileTransferEntry> get conflicts => entries.where((e) => e.hasConflict);

  bool get hasConflicts => entries.any((e) => e.hasConflict);

  /// How many entries transfer with no decision from the user.
  int get readyCount => entries.where((e) => !e.hasConflict).length;

  int get totalBytes => entries.fold(0, (sum, e) => sum + e.size);

  /// Whether this paste is a move that has to cross a volume, which means
  /// copy-then-delete rather than a rename: slow, and interruptible partway.
  bool get crossVolume =>
      mode == FileTransferMode.move && entries.any((e) => e.crossVolume);
}

/// Where a running transfer has got to.
///
/// Granularity is one file. [File.copy] is a single OS-level call with no
/// progress of its own, and going chunked to report inside a file would cost
/// more throughput than the readout is worth.
class FileTransferProgress {
  /// 0-based index of the entry being worked on; equals [total] on the final
  /// callback, which reports the finished totals.
  final int index;
  final int total;
  final String name;
  final int bytesDone;
  final int bytesTotal;

  const FileTransferProgress({
    required this.index,
    required this.total,
    required this.name,
    required this.bytesDone,
    required this.bytesTotal,
  });
}

class FileTransferFailure {
  final String sourcePath;
  final String message;

  const FileTransferFailure(this.sourcePath, this.message);
}

/// What actually happened.
///
/// Every entry lands in exactly one of the three lists, except in a run
/// stopped by [cancelled], where the untouched tail is in none of them.
class FileTransferOutcome {
  /// Final target paths of the files that arrived.
  final List<String> succeeded;

  /// Source paths that were deliberately not touched.
  final List<String> skipped;

  final List<FileTransferFailure> failed;

  final bool cancelled;

  const FileTransferOutcome({
    required this.succeeded,
    required this.skipped,
    required this.failed,
    required this.cancelled,
  });

  bool get isClean => failed.isEmpty && !cancelled;
}

/// Bulk move/copy behind the file browser's staging area.
///
/// Two phases on purpose. [plan] reads the disk and reports what would go
/// wrong; [execute] performs exactly what the plan plus the caller's
/// resolutions describe. Anything that would destroy a file — an overwrite, a
/// move onto itself — is guarded again at execution time.
class FileTransferService {
  const FileTransferService._();

  /// Resolves [sourcePaths] against [destination] without writing anything.
  static Future<FileTransferPlan> plan({
    required Iterable<String> sourcePaths,
    required String destination,
    required FileTransferMode mode,
  }) async {
    final destinationExists = await Directory(destination).exists();
    final entries = <FileTransferEntry>[];
    final plannedTargets = <String>[];

    for (final source in sourcePaths) {
      final name = p.basename(source);
      final target = p.join(destination, name);
      final file = File(source);
      final sourceExists = await file.exists();

      var size = 0;
      if (sourceExists) {
        try {
          size = await file.length();
        } on FileSystemException {
          // Present but unreadable. It still transfers; only the byte readout
          // is poorer for it.
        }
      }

      final FileTransferConflict conflict;
      if (!sourceExists) {
        conflict = FileTransferConflict.sourceMissing;
      } else if (p.equals(p.dirname(source), destination)) {
        conflict = FileTransferConflict.sameLocation;
      } else if (plannedTargets.any((t) => p.equals(t, target))) {
        conflict = FileTransferConflict.duplicateInBatch;
      } else if (await File(target).exists()) {
        conflict = FileTransferConflict.targetExists;
      } else {
        conflict = FileTransferConflict.none;
      }

      plannedTargets.add(target);
      entries.add(FileTransferEntry(
        sourcePath: source,
        name: name,
        size: size,
        targetPath: target,
        conflict: conflict,
        crossVolume: isLikelyCrossVolume(source, destination),
      ));
    }

    return FileTransferPlan(
      mode: mode,
      destination: destination,
      destinationExists: destinationExists,
      entries: entries,
    );
  }

  /// Performs [plan], applying [resolutions] keyed by source path.
  ///
  /// A conflicted entry with no resolution is skipped. [isCancelled] is
  /// consulted between files, so cancelling stops the run without ever leaving
  /// a half-written file behind.
  static Future<FileTransferOutcome> execute(
    FileTransferPlan plan, {
    Map<String, FileConflictResolution> resolutions = const {},
    void Function(FileTransferProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final succeeded = <String>[];
    final skipped = <String>[];
    final failed = <FileTransferFailure>[];

    final total = plan.entries.length;
    final bytesTotal = plan.totalBytes;
    var bytesDone = 0;
    var cancelled = false;

    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }

      final entry = plan.entries[i];
      onProgress?.call(FileTransferProgress(
        index: i,
        total: total,
        name: entry.name,
        bytesDone: bytesDone,
        bytesTotal: bytesTotal,
      ));

      var resolution = resolutions[entry.sourcePath];
      if (entry.hasConflict && resolution == null) {
        resolution = FileConflictResolution.skip;
      }

      if (entry.conflict == FileTransferConflict.sourceMissing ||
          resolution == FileConflictResolution.skip) {
        skipped.add(entry.sourcePath);
        continue;
      }

      // No `reserved` set needed here, unlike a preview that numbers several
      // conflicts at once: this loop awaits each file, so an earlier rename in
      // the same run is already on disk by the time the next one looks for a
      // free name.
      final target = resolution == FileConflictResolution.rename
          ? uniqueTargetPath(plan.destination, entry.name)
          : entry.targetPath;

      // The one thing that must never happen. A `sameLocation` entry resolved
      // with overwrite reaches the delete below pointing at its own source,
      // and the file would be gone before anything was written in its place.
      if (p.equals(target, entry.sourcePath)) {
        skipped.add(entry.sourcePath);
        continue;
      }

      try {
        if (resolution == FileConflictResolution.overwrite) {
          final existing = File(target);
          if (await existing.exists()) {
            await existing.delete();
          }
        }

        if (plan.mode == FileTransferMode.copy) {
          await File(entry.sourcePath).copy(target);
        } else {
          try {
            await File(entry.sourcePath).rename(target);
          } on FileSystemException {
            // Almost always a cross-device rename, which no platform allows.
            // Caught broadly rather than by errno: the codes differ per
            // platform, and a genuine permission error simply fails the copy
            // below and is reported the way it would have been anyway.
            await File(entry.sourcePath).copy(target);

            // The one place a cancel can arrive mid-file. A cross-volume move
            // is a copy and *then* a delete, and the copy is the long half —
            // so the check goes between them, and a cancel that lands here
            // rolls the copy back rather than completing a move the user just
            // stopped. `12f` promises exactly this: the copy is undone, the
            // source stays put.
            if (isCancelled?.call() ?? false) {
              try {
                await File(target).delete();
              } on FileSystemException {
                // Nothing better to do: the source is still there, which is
                // the half that matters.
              }
              cancelled = true;
              break;
            }

            try {
              await File(entry.sourcePath).delete();
            } on FileSystemException catch (e) {
              // The copy landed, so the destination is complete — but the
              // move did not, and the user now has two of the file. Reported
              // as a failure precisely because the tidy-up is theirs.
              bytesDone += entry.size;
              failed.add(FileTransferFailure(
                entry.sourcePath,
                'Copied to $target, but the original could not be removed: ${e.message}',
              ));
              continue;
            }
          }
        }

        succeeded.add(target);
        bytesDone += entry.size;
      } on FileSystemException catch (e) {
        failed.add(FileTransferFailure(entry.sourcePath, e.message));
      }
    }

    onProgress?.call(FileTransferProgress(
      index: total,
      total: total,
      name: '',
      bytesDone: bytesDone,
      bytesTotal: bytesTotal,
    ));

    return FileTransferOutcome(
      succeeded: succeeded,
      skipped: skipped,
      failed: failed,
      cancelled: cancelled,
    );
  }

  /// Counts up a numbered suffix until the name is free: `foo.png` becomes
  /// `foo (2).png`, then `foo (3).png`.
  ///
  /// [reserved] holds names claimed earlier in the same run, which are not on
  /// disk yet and so cannot be found by looking.
  static String uniqueTargetPath(
    String directory,
    String fileName, {
    Set<String>? reserved,
  }) {
    final stem = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);

    var candidate = p.join(directory, fileName);
    var counter = 1;
    while (_isTaken(candidate, reserved)) {
      counter++;
      candidate = p.join(directory, '$stem ($counter)$extension');
    }
    return candidate;
  }

  static bool _isTaken(String path, Set<String>? reserved) {
    if (reserved != null && reserved.any((r) => p.equals(r, path))) return true;
    return File(path).existsSync() || Directory(path).existsSync();
  }

  /// Whether a move between these two paths has to cross a volume.
  ///
  /// Compares root prefixes, which answers the question on Windows (`D:` vs
  /// `E:`, or two different UNC shares) and never on POSIX, where every path
  /// roots at `/` regardless of what is mounted where. So this is a hint for
  /// the UI — "this one will be slow" — and not a branch the transfer depends
  /// on: [execute] finds out for real when the rename fails and falls back.
  static bool isLikelyCrossVolume(String source, String destination) {
    final a = p.rootPrefix(p.absolute(source));
    final b = p.rootPrefix(p.absolute(destination));
    if (a.isEmpty || b.isEmpty) return false;
    return !p.equals(a, b);
  }
}
