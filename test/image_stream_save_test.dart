import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// A streamed image task saves each image the moment it arrives. On Ark a
/// Seedream group streams one image per event, minutes apart; the executor
/// used to hold them all until the stream ended, so the first result showed
/// up only with the last — and a failure late in the group lost the finished
/// (and billed) ones.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dataDir = usePrivateDataDir('joycai_image_stream_save_test');
  // The test binding answers every HttpClient request with a 400; this test
  // talks to a real loopback server.
  setUpAll(() => HttpOverrides.global = null);

  test('the first image is on disk while the stream is still open', () async {
    final release = Completer<void>();
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
      // Unbuffered, so the first event leaves before the second is written —
      // the server's buffer would otherwise hold it despite the flush.
      request.response
        ..bufferOutput = false
        ..headers.contentType = ContentType('text', 'event-stream');
      void event(Map<String, dynamic> data) => request.response
          .write('event: ${data['type']}\ndata: ${jsonEncode(data)}\n\n');
      event({
        'type': 'image_generation.partial_succeeded',
        'image_index': 0,
        'url': '$base/img/0.png',
      });
      await request.response.flush();
      await release.future; // The second image is "still being drawn".
      event({
        'type': 'image_generation.partial_succeeded',
        'image_index': 1,
        'url': '$base/img/1.png',
      });
      event({
        'type': 'image_generation.completed',
        'usage': {'generated_images': 2},
      });
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final outDir = Directory('${dataDir.path}/out')..createSync();
    final db = DatabaseService();
    await db.saveSetting('output_directory', outDir.path);
    final channelId = await db.addChannel({
      'display_name': 'Ark',
      'endpoint': 'http://127.0.0.1:${server.port}/api/plan/v3',
      'api_key': 'k',
      'type': Vendors.volcengineArk,
    });
    final modelId = await db.addModel({
      'model_id': 'doubao-seedream-5.0-lite',
      'model_name': 'Seedream lite',
      'tag': 'image',
      'channel_id': channelId,
    });

    final queue = TaskQueueService();
    addTearDown(queue.dispose);
    final saved = <String>[];
    final firstSaved = Completer<void>();
    final sub = queue.eventStream.listen((e) {
      if (e.taskId != 'stream-save' || e.type != TaskEventType.imageResult) {
        return;
      }
      saved.add(e.data as String);
      if (!firstSaved.isCompleted) firstSaved.complete();
    });
    addTearDown(sub.cancel);

    await queue.addTask(const [], modelId,
        {'prompt': 'two posters', 'maxImages': '2', 'watermark': 'off'},
        id: 'stream-save');

    final task = queue.queue.firstWhere((t) => t.id == 'stream-save');
    await firstSaved.future.timeout(const Duration(seconds: 20),
        onTimeout: () => fail('no image saved: ${task.logs.join('\n')}'));
    expect(release.isCompleted, isFalse);
    expect(saved, hasLength(1));
    expect(File(saved.single).existsSync(), isTrue);

    release.complete();
    for (var i = 0; i < 200 && task.status != TaskStatus.completed; i++) {
      if (task.status == TaskStatus.failed) {
        fail('task failed: ${task.logs.join('\n')}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(task.status, TaskStatus.completed);
    expect(task.resultPaths, hasLength(2));
    expect(saved, hasLength(2));
  });
}

/// A 1×1 transparent PNG.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
