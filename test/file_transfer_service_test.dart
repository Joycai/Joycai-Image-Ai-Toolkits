import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/file_transfer_service.dart';
import 'package:path/path.dart' as p;

/// Covers the move/copy behind the file browser's staging area.
///
/// Everything here runs against real files in a real temp directory. The
/// failures this guards against are all destructive — a file overwritten, a
/// source deleted before its copy landed, a rename that quietly clobbered the
/// previous rename — and none of them are visible against a mocked filesystem,
/// which is exactly where they would be mocked away.
void main() {
  late Directory root;
  late Directory sourceDir;
  late Directory otherDir;
  late Directory destDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('joycai_transfer');
    sourceDir = await Directory(p.join(root.path, 'source')).create();
    otherDir = await Directory(p.join(root.path, 'other')).create();
    destDir = await Directory(p.join(root.path, 'dest')).create();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<String> write(Directory dir, String name, String contents) async {
    final file = File(p.join(dir.path, name));
    await file.writeAsString(contents);
    return file.path;
  }

  Future<FileTransferPlan> planFor(
    List<String> sources, {
    FileTransferMode mode = FileTransferMode.copy,
    Directory? destination,
  }) =>
      FileTransferService.plan(
        sourcePaths: sources,
        destination: (destination ?? destDir).path,
        mode: mode,
      );

  group('plan', () {
    test('a clean paste reports no conflicts', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');
      final b = await write(sourceDir, 'b.png', 'bb');

      final plan = await planFor([a, b]);

      expect(plan.hasConflicts, isFalse);
      expect(plan.readyCount, 2);
      expect(plan.destinationExists, isTrue);
      // Sizes are read off the disk, not carried in from the caller's stale
      // listing — the progress readout is only as honest as this.
      expect(plan.totalBytes, 5);
    });

    test('names an existing file at the destination', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');
      await write(destDir, 'a.png', 'old');

      final plan = await planFor([a]);

      expect(plan.entries.single.conflict, FileTransferConflict.targetExists);
      expect(plan.readyCount, 0);
    });

    test('two staged files landing on one name collide with each other',
        () async {
      // Neither is at the destination, so a plain "does the target exist"
      // check sees nothing wrong with either of them. The collision is
      // between the two, and only shows up if the plan remembers what the
      // earlier entries claimed.
      final a = await write(sourceDir, 'shot.png', 'one');
      final b = await write(otherDir, 'shot.png', 'two');

      final plan = await planFor([a, b]);

      expect(plan.entries.first.conflict, FileTransferConflict.none);
      expect(plan.entries.last.conflict, FileTransferConflict.duplicateInBatch);
    });

    test('a file already in the destination folder is sameLocation', () async {
      final a = await write(destDir, 'a.png', 'aaa');

      final plan = await planFor([a]);

      expect(plan.entries.single.conflict, FileTransferConflict.sameLocation);
    });

    test('a mark whose file has gone is sourceMissing', () async {
      // Staging holds a mark, not a lock. Between staging and pasting, the
      // file can be moved by anything on the machine.
      final ghost = p.join(sourceDir.path, 'gone.png');

      final plan = await planFor([ghost]);

      expect(plan.entries.single.conflict, FileTransferConflict.sourceMissing);
      expect(plan.entries.single.size, 0);
    });

    test('a missing destination is reported once, not per file', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');
      final vanished = Directory(p.join(root.path, 'nowhere'));

      final plan = await planFor([a], destination: vanished);

      expect(plan.destinationExists, isFalse);
      expect(plan.entries.single.conflict, FileTransferConflict.none);
    });

    test('a directory at the target name is a conflict too', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');
      await Directory(p.join(destDir.path, 'a.png')).create();

      final plan = await planFor([a]);

      expect(plan.entries.single.conflict, FileTransferConflict.targetExists);
    });
  });

  group('uniqueTargetPath', () {
    test('counts up from (2), skipping every taken name', () async {
      await write(destDir, 'a.png', 'x');

      expect(
        p.basename(FileTransferService.uniqueTargetPath(destDir.path, 'a.png')),
        'a (2).png',
      );

      await write(destDir, 'a (2).png', 'x');

      expect(
        p.basename(FileTransferService.uniqueTargetPath(destDir.path, 'a.png')),
        'a (3).png',
      );
    });

    test('honours names claimed earlier in the same run', () async {
      // The second rename of a run looks for a file the first one has not
      // written yet. Without the reserved set both pick (2) and the first
      // loses.
      await write(destDir, 'a.png', 'x');
      final claimed = {p.join(destDir.path, 'a (2).png')};

      expect(
        p.basename(FileTransferService.uniqueTargetPath(destDir.path, 'a.png',
            reserved: claimed)),
        'a (3).png',
      );
    });

    test('leaves a free name alone', () {
      expect(
        p.basename(
            FileTransferService.uniqueTargetPath(destDir.path, 'fresh.png')),
        'fresh.png',
      );
    });
  });

  group('execute', () {
    test('copy lands the file and leaves the source', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');

      final outcome = await FileTransferService.execute(await planFor([a]));

      expect(outcome.isClean, isTrue);
      expect(outcome.succeeded, [p.join(destDir.path, 'a.png')]);
      expect(File(a).existsSync(), isTrue);
      expect(File(p.join(destDir.path, 'a.png')).readAsStringSync(), 'aaa');
    });

    test('move lands the file and takes the source away', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');

      final outcome = await FileTransferService.execute(
          await planFor([a], mode: FileTransferMode.move));

      expect(outcome.succeeded.length, 1);
      expect(File(a).existsSync(), isFalse);
      expect(File(p.join(destDir.path, 'a.png')).readAsStringSync(), 'aaa');
    });

    test('an undecided conflict is skipped, never resolved by default',
        () async {
      final a = await write(sourceDir, 'a.png', 'new');
      await write(destDir, 'a.png', 'old');

      final outcome = await FileTransferService.execute(await planFor([a]));

      expect(outcome.skipped, [a]);
      expect(outcome.succeeded, isEmpty);
      expect(File(p.join(destDir.path, 'a.png')).readAsStringSync(), 'old');
    });

    test('a target created after planning is not silently overwritten',
        () async {
      final a = await write(sourceDir, 'a.png', 'new');
      final plan = await planFor([a]);
      await write(destDir, 'a.png', 'arrived later');

      final outcome = await FileTransferService.execute(plan);

      expect(outcome.skipped, [a]);
      expect(outcome.succeeded, isEmpty);
      expect(File(a).readAsStringSync(), 'new');
      expect(
        File(p.join(destDir.path, 'a.png')).readAsStringSync(),
        'arrived later',
      );
    });

    test('a move also preserves a target created after planning', () async {
      final a = await write(sourceDir, 'a.png', 'new');
      final plan = await planFor([a], mode: FileTransferMode.move);
      await write(destDir, 'a.png', 'arrived later');

      final outcome = await FileTransferService.execute(plan);

      expect(outcome.skipped, [a]);
      expect(File(a).readAsStringSync(), 'new');
      expect(
        File(p.join(destDir.path, 'a.png')).readAsStringSync(),
        'arrived later',
      );
    });

    test('overwrite replaces the file at the destination', () async {
      final a = await write(sourceDir, 'a.png', 'new');
      await write(destDir, 'a.png', 'old');

      final outcome = await FileTransferService.execute(
        await planFor([a]),
        resolutions: {a: FileConflictResolution.overwrite},
      );

      expect(outcome.succeeded.length, 1);
      expect(File(p.join(destDir.path, 'a.png')).readAsStringSync(), 'new');
    });

    test('rename keeps both files', () async {
      final a = await write(sourceDir, 'a.png', 'new');
      await write(destDir, 'a.png', 'old');

      await FileTransferService.execute(
        await planFor([a]),
        resolutions: {a: FileConflictResolution.rename},
      );

      expect(File(p.join(destDir.path, 'a.png')).readAsStringSync(), 'old');
      expect(File(p.join(destDir.path, 'a (2).png')).readAsStringSync(), 'new');
    });

    test('overwriting a file onto itself does not delete it', () async {
      // The destructive one. A `sameLocation` entry's target *is* its source,
      // so the overwrite branch's delete would take the file out and leave
      // nothing to put back. Reachable from the UI by staging a file, then
      // pasting into the folder it already sits in and choosing "overwrite
      // all".
      final a = await write(destDir, 'a.png', 'precious');

      final outcome = await FileTransferService.execute(
        await planFor([a], mode: FileTransferMode.move),
        resolutions: {a: FileConflictResolution.overwrite},
      );

      expect(File(a).existsSync(), isTrue);
      expect(File(a).readAsStringSync(), 'precious');
      expect(outcome.skipped, [a]);
      expect(outcome.succeeded, isEmpty);
    });

    test('two renames in one run do not land on the same name', () async {
      final a = await write(sourceDir, 'shot.png', 'one');
      final b = await write(otherDir, 'shot.png', 'two');
      await write(destDir, 'shot.png', 'existing');

      await FileTransferService.execute(
        await planFor([a, b]),
        resolutions: {
          a: FileConflictResolution.rename,
          b: FileConflictResolution.rename,
        },
      );

      expect(File(p.join(destDir.path, 'shot.png')).readAsStringSync(),
          'existing');
      expect(
          File(p.join(destDir.path, 'shot (2).png')).readAsStringSync(), 'one');
      expect(
          File(p.join(destDir.path, 'shot (3).png')).readAsStringSync(), 'two');
    });

    test('cancelling stops between files and leaves the tail alone', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');
      final b = await write(sourceDir, 'b.png', 'bbb');
      final c = await write(sourceDir, 'c.png', 'ccc');

      var seen = 0;
      final outcome = await FileTransferService.execute(
        await planFor([a, b, c], mode: FileTransferMode.move),
        isCancelled: () => seen++ >= 2,
      );

      expect(outcome.cancelled, isTrue);
      expect(outcome.succeeded.length, 2);
      // Untouched, and in neither the succeeded nor the skipped list: a
      // cancelled run does not pretend to have decided about the rest.
      expect(File(c).existsSync(), isTrue);
      expect(outcome.skipped, isEmpty);
    });

    test('a failure is collected, not thrown, and the run continues', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');
      final b = await write(sourceDir, 'b.png', 'bbb');
      final vanished = Directory(p.join(root.path, 'nowhere'));

      final outcome = await FileTransferService.execute(
          await planFor([a, b], destination: vanished));

      expect(outcome.failed.length, 2);
      expect(outcome.failed.first.sourcePath, a);
      expect(outcome.isClean, isFalse);
      // Nothing was moved out from under the user on the way to failing.
      expect(File(a).existsSync(), isTrue);
    });

    test('progress ends on the full count and the full byte total', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');
      final b = await write(sourceDir, 'b.png', 'bb');

      final seen = <FileTransferProgress>[];
      await FileTransferService.execute(
        await planFor([a, b]),
        onProgress: seen.add,
      );

      expect(seen.first.index, 0);
      expect(seen.first.name, 'a.png');
      expect(seen.last.index, 2);
      expect(seen.last.bytesDone, 5);
      expect(seen.last.bytesTotal, 5);
    });
  });

  group('cross-volume move (copy then delete)', () {
    // `forceCopyDelete` drives the same helper the real cross-device fallback
    // reaches. The path only runs when source and destination sit on different
    // volumes, which one machine cannot arrange in a test — and it is the path
    // that deletes files, so it is the last one that should go unexercised.

    test('completes the move the long way round', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');

      final outcome = await FileTransferService.execute(
        await planFor([a], mode: FileTransferMode.move),
        forceCopyDelete: true,
      );

      expect(outcome.isClean, isTrue);
      expect(File(a).existsSync(), isFalse);
      expect(File(p.join(destDir.path, 'a.png')).readAsStringSync(), 'aaa');
    });

    test('a cancel between the copy and the delete rolls the copy back',
        () async {
      // The promise `12f` makes to the user in as many words: the copy is
      // undone, the source stays put. Without the rollback the destination
      // would keep a file from a run the user stopped, and the progress dialog
      // said it would not.
      final a = await write(sourceDir, 'a.png', 'aaa');

      final outcome = await FileTransferService.execute(
        await planFor([a], mode: FileTransferMode.move),
        forceCopyDelete: true,
        // Only true once the copy has happened: `execute` asks before each
        // file and again between the halves, so the second ask is this one.
        isCancelled: () => File(p.join(destDir.path, 'a.png')).existsSync(),
      );

      expect(outcome.cancelled, isTrue);
      expect(outcome.succeeded, isEmpty);
      expect(File(a).readAsStringSync(), 'aaa');
      expect(File(p.join(destDir.path, 'a.png')).existsSync(), isFalse);
    });

    test('a cancel before the first file copies nothing at all', () async {
      final a = await write(sourceDir, 'a.png', 'aaa');

      final outcome = await FileTransferService.execute(
        await planFor([a], mode: FileTransferMode.move),
        forceCopyDelete: true,
        isCancelled: () => true,
      );

      expect(outcome.cancelled, isTrue);
      expect(File(a).existsSync(), isTrue);
      expect(File(p.join(destDir.path, 'a.png')).existsSync(), isFalse);
    });

    test('the files already moved before a cancel stay moved', () async {
      // The rollback is per-file, not per-run: a move that finished is done,
      // and undoing it would mean putting a file back from a source that is
      // already gone. Cancelling on `b`'s arrival lets `a` complete first.
      final a = await write(sourceDir, 'a.png', 'aaa');
      final b = await write(sourceDir, 'b.png', 'bbb');

      final outcome = await FileTransferService.execute(
        await planFor([a, b], mode: FileTransferMode.move),
        forceCopyDelete: true,
        isCancelled: () => File(p.join(destDir.path, 'b.png')).existsSync(),
      );

      expect(outcome.cancelled, isTrue);
      // `a` went the whole way.
      expect(File(p.join(destDir.path, 'a.png')).readAsStringSync(), 'aaa');
      expect(File(a).existsSync(), isFalse);
      // `b` was rolled back: nothing at the destination, source untouched.
      expect(File(p.join(destDir.path, 'b.png')).existsSync(), isFalse);
      expect(File(b).readAsStringSync(), 'bbb');
      expect(outcome.succeeded, [p.join(destDir.path, 'a.png')]);
    });
  });

  group('isLikelyCrossVolume', () {
    test('two paths under one root are not', () {
      expect(
        FileTransferService.isLikelyCrossVolume(
            p.join(sourceDir.path, 'a.png'), destDir.path),
        isFalse,
      );
    });

    test('two drive letters are, on Windows', () {
      // POSIX roots everything at `/`, so there is nothing to compare and the
      // fallback in execute is the only thing that finds out. Documented in
      // the method; asserted only where the answer exists.
      if (!Platform.isWindows) return;

      expect(
        FileTransferService.isLikelyCrossVolume(
            r'C:\pictures\a.png', r'D:\archive'),
        isTrue,
      );
    });
  });
}
