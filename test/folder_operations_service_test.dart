import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/file_transfer_service.dart';
import 'package:joycai_image_ai_toolkits/services/folder_operations_service.dart';
import 'package:path/path.dart' as p;

/// Covers the folder management behind the file browser's tree.
///
/// Real directories in a real temp folder, for the same reason the file
/// transfer tests use them: every failure this guards against is destructive
/// — a tree deleted before its copy landed, a folder moved into itself, a
/// name that silently clobbered a sibling — and a mocked filesystem is
/// exactly where those would be mocked away.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('joycai_folder_ops');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Directory> mkdir(String relative) =>
      Directory(p.join(root.path, relative)).create(recursive: true);

  Future<File> write(String relative, String contents) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsString(contents);
  }

  group('validateName', () {
    test('rejects empty, illegal, reserved and taken names in that order', () async {
      await mkdir('parent/taken');
      final parent = p.join(root.path, 'parent');

      FolderNameError? check(String name, {bool windows = true}) =>
          FolderOperationsService.validateName(parent: parent, name: name, windows: windows);

      expect(check(''), FolderNameError.empty);
      expect(check('   '), FolderNameError.empty);
      expect(check('a/b'), FolderNameError.illegalChars);
      expect(check(r'a\b'), FolderNameError.illegalChars);
      expect(check('a:b'), FolderNameError.illegalChars);
      expect(check('ab'), FolderNameError.illegalChars);
      expect(check('CON'), FolderNameError.reservedName);
      expect(check('lpt1.txt'), FolderNameError.reservedName);
      // Reserved names are a Windows thing.
      expect(check('CON', windows: false), isNull);
      expect(check('taken'), FolderNameError.exists);
      expect(check('fresh'), isNull);
    });

    test('a trailing dot or space on Windows is trimmed, not refused', () {
      final parent = root.path;
      expect(FolderOperationsService.validateName(parent: parent, name: 'name. ', windows: true), isNull);
      expect(FolderOperationsService.sanitize('name. ', windows: true), 'name');
      expect(FolderOperationsService.sanitize('name. ', windows: false), 'name.');
    });

    test('renaming a folder to its own name is not "exists"', () async {
      final own = await mkdir('own');
      expect(
        FolderOperationsService.validateName(
          parent: root.path,
          name: 'own',
          currentPath: own.path,
        ),
        isNull,
      );
    });

    test('a path already registered in the tree is refused', () async {
      final registered = p.join(root.path, 'lib');
      expect(
        FolderOperationsService.validateName(
          parent: root.path,
          name: 'lib',
          registered: {registered},
        ),
        FolderNameError.registered,
      );
    });
  });

  group('create / rename / delete', () {
    test('create returns the new path and sanitises the name', () async {
      final created = await FolderOperationsService.create(root.path, '  sketch  ');
      expect(p.basename(created), 'sketch');
      expect(await Directory(created).exists(), isTrue);
    });

    test('rename keeps the folder in place under the new name', () async {
      final dir = await mkdir('before');
      await write('before/inner/a.txt', 'a');

      final renamed = await FolderOperationsService.rename(dir.path, 'after');

      expect(p.dirname(renamed), p.dirname(dir.path));
      expect(p.basename(renamed), 'after');
      expect(await File(p.join(renamed, 'inner', 'a.txt')).exists(), isTrue);
      expect(await dir.exists(), isFalse);
    });

    test('rename to the same name is a no-op that returns the path', () async {
      final dir = await mkdir('same');
      expect(await FolderOperationsService.rename(dir.path, 'same'), dir.path);
      expect(await dir.exists(), isTrue);
    });

    test('inventory counts folders, files and bytes recursively', () async {
      await mkdir('inv/a/b');
      await write('inv/one.txt', '12345');
      await write('inv/a/two.txt', '12');

      final inventory = await FolderOperationsService.inventory(p.join(root.path, 'inv'));

      expect(inventory.folders, 2);
      expect(inventory.files, 2);
      expect(inventory.bytes, 7);
      expect(inventory.items, 4);
      expect(inventory.isEmpty, isFalse);
    });

    test('permanent delete removes the whole tree', () async {
      final dir = await mkdir('gone/deep');
      await write('gone/deep/x.txt', 'x');

      await FolderOperationsService.delete(p.join(root.path, 'gone'), toTrash: false);

      expect(await dir.exists(), isFalse);
      expect(await Directory(p.join(root.path, 'gone')).exists(), isFalse);
    });
  });

  group('canTransfer', () {
    test('refuses self, descendants, the current parent, roots and clashes', () async {
      final src = await mkdir('src');
      final child = await mkdir('src/child');
      final other = await mkdir('other');
      await mkdir('other/src');
      final free = await mkdir('free');

      FolderMoveRejection? can(String s, String d, {Set<String> roots = const {}, FolderTransferMode mode = FolderTransferMode.move}) =>
          FolderOperationsService.canTransfer(s, d, roots: roots, mode: mode);

      expect(can(src.path, src.path), FolderMoveRejection.intoSelf);
      expect(can(src.path, child.path), FolderMoveRejection.intoDescendant);
      expect(can(src.path, root.path), FolderMoveRejection.sameParent);
      expect(can(src.path, other.path), FolderMoveRejection.targetExists);
      expect(can(src.path, free.path, roots: {src.path}), FolderMoveRejection.isRoot);
      expect(can(src.path, free.path), isNull);
    });

    test('a copy may go back to its own parent and may take a root', () async {
      final src = await mkdir('src2');
      final free = await mkdir('free2');
      expect(
        FolderOperationsService.canTransfer(src.path, root.path, mode: FolderTransferMode.copy),
        FolderMoveRejection.targetExists,
      );
      expect(
        FolderOperationsService.canTransfer(src.path, free.path, roots: {src.path}, mode: FolderTransferMode.copy),
        isNull,
      );
    });
  });

  group('transfer', () {
    test('a same-volume move is one rename and reports no copying', () async {
      final src = await mkdir('mv');
      await write('mv/a.txt', 'a');
      final dest = await mkdir('dest');

      final outcome = await FolderOperationsService.transfer(
        src.path,
        dest.path,
        mode: FolderTransferMode.move,
      );

      expect(outcome.copied, isFalse);
      expect(outcome.isClean, isTrue);
      expect(outcome.targetPath, p.join(dest.path, 'mv'));
      expect(await File(p.join(dest.path, 'mv', 'a.txt')).exists(), isTrue);
      expect(await src.exists(), isFalse);
    });

    test('the copy route reproduces the tree, reports bytes, then removes the source', () async {
      final src = await mkdir('cp');
      await write('cp/a.txt', 'aaa');
      await write('cp/sub/deep/b.txt', 'bb');
      await mkdir('cp/empty');
      final dest = await mkdir('dest');
      final seen = <FileTransferProgress>[];

      final outcome = await FolderOperationsService.transfer(
        src.path,
        dest.path,
        mode: FolderTransferMode.move,
        onProgress: seen.add,
        forceCopyDelete: true,
      );

      expect(outcome.copied, isTrue);
      expect(outcome.isClean, isTrue);
      expect(outcome.filesDone, 2);
      expect(outcome.filesTotal, 2);
      expect(seen.last.bytesDone, 5);
      expect(seen.last.bytesTotal, 5);
      final target = p.join(dest.path, 'cp');
      expect(await File(p.join(target, 'a.txt')).readAsString(), 'aaa');
      expect(await File(p.join(target, 'sub', 'deep', 'b.txt')).readAsString(), 'bb');
      expect(await Directory(p.join(target, 'empty')).exists(), isTrue);
      expect(await src.exists(), isFalse);
    });

    test('a copy leaves the source in place', () async {
      final src = await mkdir('keep');
      await write('keep/a.txt', 'a');
      final dest = await mkdir('dest');

      final outcome = await FolderOperationsService.transfer(
        src.path,
        dest.path,
        mode: FolderTransferMode.copy,
      );

      expect(outcome.copied, isTrue);
      expect(await File(p.join(dest.path, 'keep', 'a.txt')).exists(), isTrue);
      expect(await File(p.join(src.path, 'a.txt')).exists(), isTrue);
    });

    test('cancelling mid-copy keeps the source whole and the partial copy', () async {
      final src = await mkdir('cancel');
      await write('cancel/1.txt', '1');
      await write('cancel/2.txt', '2');
      await write('cancel/3.txt', '3');
      final dest = await mkdir('dest');
      var filesStarted = 0;

      final outcome = await FolderOperationsService.transfer(
        src.path,
        dest.path,
        mode: FolderTransferMode.move,
        onProgress: (progress) {
          if (progress.name.isNotEmpty) filesStarted++;
        },
        // Stop once one file is through.
        isCancelled: () => filesStarted >= 1,
        forceCopyDelete: true,
      );

      expect(outcome.cancelled, isTrue);
      expect(outcome.filesDone, 1);
      expect(outcome.filesTotal, 3);
      // Source untouched.
      expect(Directory(src.path).listSync().whereType<File>().length, 3);
      // What arrived stays.
      expect(Directory(p.join(dest.path, 'cancel')).listSync().whereType<File>().length, 1);
    });

    test('moving a folder into itself is refused at execution too', () async {
      final src = await mkdir('self');
      await expectLater(
        FolderOperationsService.transfer(src.path, src.path, mode: FolderTransferMode.move),
        throwsA(isA<FileSystemException>()),
      );
      expect(await src.exists(), isTrue);
    });
  });
}
