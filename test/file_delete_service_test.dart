import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/files/file_delete_service.dart';
import 'package:joycai_image_ai_toolkits/services/files/trash_service.dart';
import 'package:path/path.dart' as p;

/// Covers deleting files from the browser.
///
/// Real files in a real temp folder, for the reason the transfer and folder
/// tests give: what this guards against is a user's files going away when
/// they should not have, and a mocked filesystem is exactly where that would
/// be mocked away. The trash is the one thing stubbed — it is the platform's,
/// not ours, and a test must never put anything in the developer's bin.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('joycai_file_delete');
    TrashService.overrideSupport(false);
  });

  tearDown(() async {
    TrashService.overrideSupport(null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> write(String relative) async {
    final file = File(p.join(root.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsString('x');
  }

  test('deletes every file it was given', () async {
    final a = await write('a.png');
    final b = await write('sub/b.png');

    final outcome = await FileDeleteService.delete(
      [a.path, b.path],
      toTrash: false,
    );

    expect(outcome.isClean, isTrue);
    expect(outcome.deleted, [a.path, b.path]);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
  });

  test('a failing entry does not stop the rest of the batch', () async {
    final a = await write('a.png');
    final missing = p.join(root.path, 'gone.png');
    final b = await write('b.png');

    final outcome = await FileDeleteService.delete(
      [a.path, missing, b.path],
      toTrash: false,
    );

    expect(outcome.deleted, [a.path, b.path]);
    expect(outcome.failed.single.path, missing);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
  });

  test('refuses a directory rather than deleting a tree', () async {
    final dir = Directory(p.join(root.path, 'folder'));
    await dir.create();
    await write('folder/inside.png');

    final outcome = await FileDeleteService.delete([dir.path], toTrash: false);

    expect(outcome.deleted, isEmpty);
    expect(outcome.failed.single.path, dir.path);
    expect(dir.existsSync(), isTrue);
  });

  test('refuses a registered root even when a caller reaches the service', () async {
    final a = await write('a.png');

    final outcome = await FileDeleteService.delete(
      [a.path],
      toTrash: false,
      protectedRoots: [a.path],
    );

    expect(outcome.deleted, isEmpty);
    expect(outcome.failed.single.path, a.path);
    expect(a.existsSync(), isTrue);
  });

  test('asking for the trash where there is none throws, and deletes nothing', () async {
    final a = await write('a.png');

    await expectLater(
      FileDeleteService.delete([a.path], toTrash: true),
      throwsA(isA<FileSystemException>()),
    );
    expect(a.existsSync(), isTrue);
  });
}
