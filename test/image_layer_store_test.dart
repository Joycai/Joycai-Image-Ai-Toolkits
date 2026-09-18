import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/image_layer.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/db/repositories/image_layer_repository.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// A layer decomposition's placement is stored beside its files
/// (`image_layers`) and follows them through the app's own renames — the
/// layer canvas reads it back to stack the layers where they came from.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dataDir = usePrivateDataDir('joycai_image_layer_store_test');
  setUpAll(() => HttpOverrides.global = null);

  File touch(String path) => File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(_png);

  group('repository', () {
    final repo = ImageLayerRepository();
    late Directory dir;

    setUp(() async {
      dir = Directory(p.join(dataDir.path, 'repo'))..createSync();
      final db = await DatabaseService().database;
      await db.delete('image_layers');
      await repo.loadPaths();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> saveSet(String folder) async {
      for (final (z, box) in [
        (0, null),
        (1, const LayerBox(27, 0, 888, 1137)),
        (2, const LayerBox(10, 10, 20, 20)),
      ]) {
        final path = p.join(folder, 'l$z.png');
        touch(path);
        await repo.save(ImageLayer(
            path: path, setId: 'set', zIndex: z, name: 'n$z', box: box));
      }
    }

    test('any file of a set finds the whole set, bottom to top', () async {
      await saveSet(dir.path);
      final set = await repo.setFor(p.join(dir.path, 'l2.png'));
      expect(set!.layers.map((l) => l.zIndex), [0, 1, 2]);
      expect(set.base!.box, isNull);
      expect(set.overlays.first.box, const LayerBox(27, 0, 888, 1137));
      expect(ImageLayerRepository.layeredPaths.value, hasLength(3));
      expect(await repo.setFor(p.join(dir.path, 'other.png')), isNull);
    });

    test('files gone from disk drop out; no layer left means no set',
        () async {
      await saveSet(dir.path);
      File(p.join(dir.path, 'l1.png')).deleteSync();
      final set = await repo.setFor(p.join(dir.path, 'l0.png'));
      expect(set!.layers.map((l) => l.zIndex), [0, 2]);

      File(p.join(dir.path, 'l2.png')).deleteSync();
      expect(await repo.setFor(p.join(dir.path, 'l0.png')), isNull);
    });

    test('a renamed file and a moved folder keep their rows', () async {
      final folder = p.join(dir.path, 'a');
      await saveSet(folder);

      final renamed = p.join(folder, 'title.png');
      File(p.join(folder, 'l1.png')).renameSync(renamed);
      await repo.move(p.join(folder, 'l1.png'), renamed);
      expect((await repo.setFor(renamed))!.layers, hasLength(3));

      final moved = p.join(dir.path, 'b');
      Directory(folder).renameSync(moved);
      await repo.move(folder, moved);
      final set = await repo.setFor(p.join(moved, 'title.png'));
      expect(set!.layers.map((l) => p.dirname(l.path)).toSet(), {moved});
      expect(ImageLayerRepository.layeredPaths.value,
          everyElement(startsWith(moved)));
    });

    test('a folder merely sharing a name prefix is left alone', () async {
      final folder = p.join(dir.path, 'a');
      await saveSet(folder);
      await saveSet(p.join(dir.path, 'ab')); // same set id, different rows
      await repo.move(folder, p.join(dir.path, 'z'));
      expect(
          ImageLayerRepository.layeredPaths.value
              .where((path) => path.startsWith(p.join(dir.path, 'ab'))),
          hasLength(3));
    });
  });

  test('a decomposition task stores base and layers with their boxes',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.method == 'GET') {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(_png);
        await request.response.close();
        return;
      }
      await utf8.decodeStream(request);
      final base = 'http://127.0.0.1:${server.port}';
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': [
          {
            'url': '$base/img/1.png',
            'z_index': 1,
            'name': 'figure',
            'description': 'the character',
            'bounding_box': {
              'absolute': [27, 0, 888, 1137],
            },
          },
          {'url': '$base/img/0.png', 'z_index': 0},
        ],
        'usage': {'generated_images': 2},
      }));
      await request.response.close();
    });

    final outDir = Directory(p.join(dataDir.path, 'out'))..createSync();
    final db = DatabaseService();
    await db.saveSetting('output_directory', outDir.path);
    final channelId = await db.addChannel({
      'display_name': 'Ark',
      'endpoint': 'http://127.0.0.1:${server.port}/api/plan/v3',
      'api_key': 'k',
      'type': Vendors.volcengineArk,
    });
    final modelId = await db.addModel({
      'model_id': 'doubao-seedream-5-0-pro-260628',
      'model_name': 'Seedream pro',
      'tag': 'image',
      'channel_id': channelId,
    });

    final queue = TaskQueueService();
    addTearDown(queue.dispose);
    await queue.addTask(const [], modelId, {'prompt': '', 'watermark': 'off'},
        id: 'layers');
    final task = queue.queue.firstWhere((t) => t.id == 'layers');
    for (var i = 0; i < 400 && task.status != TaskStatus.completed; i++) {
      if (task.status == TaskStatus.failed) fail(task.logs.join('\n'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(task.resultPaths, hasLength(2));
    final set = await ImageLayerRepository().setFor(task.resultPaths.first);
    expect(set, isNotNull, reason: task.logs.join('\n'));
    // Saved base first, so the base is the first result on disk too.
    expect(set!.base!.path, task.resultPaths.first);
    final layer = set.overlays.single;
    expect(layer.path, task.resultPaths.last);
    expect(layer.name, 'figure');
    expect(layer.description, 'the character');
    expect(layer.box, const LayerBox(27, 0, 888, 1137));
  });
}

/// A 1×1 transparent PNG.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
