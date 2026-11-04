import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_distribution.dart';
import 'package:joycai_image_ai_toolkits/services/files/persistent_media_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late PersistentMediaService storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('persistent-media-test-');
    storage = PersistentMediaService(dataDirectory: () async => p.join(root.path, 'private'));
  });
  tearDown(() => root.delete(recursive: true));

  test('direct build copies dropped bytes without a security-scope channel', () async {
    final source = await File(p.join(root.path, 'direct.png')).writeAsBytes([4, 5, 6]);
    final imported = await storage.importFile(source.path, appleBookmark: Uint8List.fromList([1]));
    expect(await File(imported).readAsBytes(), [4, 5, 6]);
  }, skip: !AppDistribution.direct);

  test('import survives original deletion and a fresh service instance', () async {
    final source = await File(p.join(root.path, 'photo.png')).writeAsBytes([1, 2, 3]);
    final imported = await storage.importFile(source.path);
    await source.delete();
    expect(await File(imported).readAsBytes(), [1, 2, 3]);
    final restarted = PersistentMediaService(
      dataDirectory: () async => p.join(root.path, 'private'),
    );
    final copies = await restarted.snapshot([imported]);
    await File(imported).delete();
    expect(await File(copies[imported]!).readAsBytes(), [1, 2, 3]);
  });

  test('same basename from different folders never overwrites another input', () async {
    final a = File(p.join(root.path, 'a', 'photo.png'));
    final b = File(p.join(root.path, 'b', 'photo.png'));
    await a.parent.create();
    await b.parent.create();
    await a.writeAsString('a');
    await b.writeAsString('b');
    final copies = await storage.snapshot([a.path, b.path, a.path]);
    expect(copies.length, 2);
    expect(await File(copies[a.path]!).readAsString(), 'a');
    expect(await File(copies[b.path]!).readAsString(), 'b');
  });

  test('failed snapshot leaves no partial accepted set and keeps originals', () async {
    final source = await File(p.join(root.path, 'source.png')).writeAsString('original');
    await expectLater(
      storage.snapshot([source.path, p.join(root.path, 'missing.png')]),
      throwsA(isA<FileSystemException>()),
    );
    final tasks = Directory(p.join(root.path, 'private', 'media', 'tasks'));
    expect(await tasks.list().toList(), isEmpty);
    expect(await source.readAsString(), 'original');
  });

  test('a vanished output folder falls back after generation without losing bytes', () async {
    final file = await storage.saveResult(
      Uint8List.fromList([9, 8, 7]),
      p.join(root.path, 'unmounted', 'paid.png'),
    );
    expect(file.parent.path, (await storage.resultsDirectory()).path);
    expect(await file.readAsBytes(), [9, 8, 7]);
    expect((await file.parent.list().toList()).length, 1);
  });

  test('fallback results are under application data and survive input cleanup', () async {
    final results = await storage.resultsDirectory();
    final file = await File(p.join(results.path, 'paid.png')).writeAsString('result');
    expect(p.isWithin(p.join(root.path, 'private'), results.path), isTrue);
    final restarted = PersistentMediaService(
      dataDirectory: () async => p.join(root.path, 'private'),
    );
    expect((await restarted.resultsDirectory()).path, results.path);
    expect(await file.readAsString(), 'result');
  });
}
