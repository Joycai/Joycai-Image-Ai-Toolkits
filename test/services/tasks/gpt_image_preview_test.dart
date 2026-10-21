import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/task_queue_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/in_memory_database.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  sqfliteFfiInit();
  for (final mode in ['success', 'failure', 'cancel']) {
    test('preview is transient through $mode and never saved or counted', () async {
      final db = await openTestDatabase();
      addTearDown(() => closeTestDatabase(db));
      final dir = Directory.systemTemp.createTempSync('gpt_preview_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      await db.saveSetting('output_directory', dir.path);
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        requests++;
        await r.drain<void>();
        r.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream');
        r.response.write(
          'data: ${jsonEncode({'type': 'image_generation.partial_image', 'b64_json': base64Encode(png)})}\n\n',
        );
        await r.response.flush();
        await release.future;
        if (mode == 'success') {
          r.response.write(
            'data: ${jsonEncode({
              'type': 'image_generation.completed',
              'b64_json': base64Encode(png),
              'usage': {'input_tokens': 12, 'output_tokens': 34, 'total_tokens': 46},
            })}\n\n',
          );
        }
        await r.response.close();
      });
      final channel = await db.addChannel(
        LLMChannel(
          displayName: 'OpenAI',
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test',
          type: Vendors.openAIRest,
        ),
      );
      final model = await db.addModel(
        LLMModel(
          modelId: 'gpt-image-2',
          modelName: 'GPT Image 2',
          channelId: channel,
          tag: 'image',
        ),
      );
      final rows = <TokenUsage>[];
      LLMService.usageSinkOverride = (row) async => rows.add(row);
      addTearDown(() => LLMService.usageSinkOverride = null);
      final queue = TaskQueueService(database: db);
      addTearDown(queue.dispose);
      await queue.ready;
      final preview = Completer<void>();
      final finished = Completer<void>();
      var saved = 0;
      queue.onTaskFinished = (_) => finished.complete();
      final sub = queue.eventStream.listen((e) {
        if (e.type == TaskEventType.imagePreview && !preview.isCompleted) preview.complete();
        if (e.type == TaskEventType.imageResult) saved++;
      });
      addTearDown(sub.cancel);
      await queue.addTask([], model, {'prompt': 'tree'}, id: 'preview');
      await preview.future.timeout(const Duration(seconds: 10));
      final task = queue.queue.single;
      expect(task.imagePreview, png);
      expect(task.withModelId('renamed').imagePreview, png);
      expect(task.resultPaths, isEmpty);
      expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
      expect(rows, isEmpty);
      expect(jsonEncode(task.toMap()), isNot(contains(base64Encode(png))));
      if (mode == 'cancel') {
        await queue.cancelTask(task.id);
        expect(task.imagePreview, isNull);
        // Keep upstream open: cancellation must release the running slot itself.
        await finished.future.timeout(const Duration(seconds: 10));
      }
      release.complete();
      await finished.future.timeout(const Duration(seconds: 10));
      expect(task.imagePreview, isNull);
      expect(task.status, switch (mode) {
        'success' => TaskStatus.completed,
        'failure' => TaskStatus.failed,
        _ => TaskStatus.cancelled,
      });
      expect(saved, mode == 'success' ? 1 : 0);
      expect(task.resultPaths.length, mode == 'success' ? 1 : 0);
      expect(rows.length, mode == 'success' ? 1 : 0);
      if (mode == 'success') {
        expect(rows.single.outputTokens, 34);
        expect(await File(task.resultPaths.single).readAsBytes(), png);
      }
      expect(requests, 1);
    });
  }
}
