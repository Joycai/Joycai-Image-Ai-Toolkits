import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';

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
      void event(Map<String, dynamic> data) =>
          request.response.write('event: ${data['type']}\ndata: ${jsonEncode(data)}\n\n');
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
    final channelId = await db.addChannel(
      LLMChannel(
        displayName: 'Ark',
        endpoint: 'http://127.0.0.1:${server.port}/api/plan/v3',
        apiKey: 'k',
        type: Vendors.volcengineArk,
      ),
    );
    final modelId = await db.addModel(
      LLMModel(
        modelId: 'doubao-seedream-5.0-lite',
        modelName: 'Seedream lite',
        tag: 'image',
        channelId: channelId,
      ),
    );

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

    await queue.addTask(const [], modelId, {
      'prompt': 'two posters',
      'maxImages': '2',
      'watermark': 'off',
    }, id: 'stream-save');

    final task = queue.queue.firstWhere((t) => t.id == 'stream-save');
    await firstSaved.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('no image saved: ${task.logs.join('\n')}'),
    );
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

  test('a stream that fails after an image keeps it and records its usage', () async {
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
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response
        ..write(
          'data: ${jsonEncode({'type': 'image_generation.partial_succeeded', 'image_index': 0, 'url': 'http://127.0.0.1:${server.port}/img/0.png'})}\n\n',
        )
        ..write(
          'data: ${jsonEncode({
            'error': {'code': 'InternalServiceError', 'message': 'boom'},
          })}\n\n',
        );
      await request.response.close();
    });

    final rows = <TokenUsage>[];
    LLMService.usageSinkOverride = (row) async => rows.add(row);
    addTearDown(() => LLMService.usageSinkOverride = null);

    final db = DatabaseService();
    final outDir = Directory('${dataDir.path}/out2')..createSync();
    await db.saveSetting('output_directory', outDir.path);
    final channelId = await db.addChannel(
      LLMChannel(
        displayName: 'Ark 2',
        endpoint: 'http://127.0.0.1:${server.port}/api/plan/v3',
        apiKey: 'k',
        type: Vendors.volcengineArk,
      ),
    );
    final modelId = await db.addModel(
      LLMModel(
        modelId: 'doubao-seedream-5.0-lite',
        modelName: 'Seedream lite 2',
        tag: 'image',
        channelId: channelId,
      ),
    );

    final queue = TaskQueueService();
    addTearDown(queue.dispose);
    await queue.addTask(const [], modelId, {
      'prompt': 'three posters',
      'maxImages': '3',
      'watermark': 'off',
    }, id: 'stream-fail');
    final task = queue.queue.firstWhere((t) => t.id == 'stream-fail');
    for (var i = 0; i < 400 && task.status != TaskStatus.failed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(task.status, TaskStatus.failed, reason: task.logs.join('\n'));
    expect(task.resultPaths, hasLength(1));
    expect(File(task.resultPaths.single).existsSync(), isTrue);
    expect(rows, hasLength(1));
  });
}

/// A 1×1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
