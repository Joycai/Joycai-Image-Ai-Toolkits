import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/token_usage.dart';
import 'package:joycai_image_ai_toolkits/services/llm/gpt_image_timeout.dart';
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
  for (final stream in [true, false]) {
    for (final cancel in [false, true]) {
      test('late GPT image stream=$stream cancel=$cancel is saved once or explicitly cancelled', () async {
        final db = await openTestDatabase();
        addTearDown(() => closeTestDatabase(db));
        final dir = Directory.systemTemp.createTempSync('gpt_late');
        addTearDown(() => dir.deleteSync(recursive: true));
        await db.saveSetting('output_directory', dir.path);
        // Exercise the persisted setting through the queue's injected DB.
        await db.saveSetting(GptImageTimeout.settingKey, '10');
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final accepted = Completer<void>();
        final deadline = Completer<void>();
        final finished = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var requests = 0;
        server.listen((r) async {
          requests++;
          await r.drain<void>();
          accepted.complete();
          await release.future;
          r.response.headers.contentType = stream
              ? ContentType('text', 'event-stream')
              : ContentType.json;
          final image = {'b64_json': base64Encode(png)};
          final usage = {'input_tokens': 3, 'output_tokens': 7, 'total_tokens': 10};
          r.response.write(
            stream
                ? 'data: ${jsonEncode({'type': 'image_generation.completed', ...image, 'usage': usage})}\n\n'
                : jsonEncode({
                    'data': [image],
                    'usage': usage,
                  }),
          );
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
            modelId: 'gpt-image-2.5-sunburst',
            modelName: 'GPT Image',
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
        queue.onTaskFinished = (_) {
          if (!finished.isCompleted) finished.complete();
        };
        var saved = 0;
        final sub = queue.eventStream.listen((event) {
          if (event.type == TaskEventType.imageResult) saved++;
        });
        addTearDown(sub.cancel);
        // Advance only the configured ten-minute deadline. Network, DB,
        // cancellation polling and all other timers use the real event loop.
        await runZoned(
          () async {
            await queue.addTask(
              [],
              model,
              {'prompt': 'tree', 'retryCount': 3},
              id: 'late',
              useStream: stream,
            );
            await accepted.future.timeout(const Duration(seconds: 10));
            await deadline.future.timeout(const Duration(seconds: 10));
            expect(queue.queue.single.status, TaskStatus.processing);
            expect(queue.queue.single.resultPaths, isEmpty);
            if (cancel) {
              await queue.cancelTask('late');
              await finished.future.timeout(const Duration(seconds: 10));
            }
            release.complete();
            await finished.future.timeout(const Duration(seconds: 10));
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              if (duration == const Duration(minutes: 10)) {
                return parent.createTimer(zone, const Duration(milliseconds: 30), () {
                  callback();
                  if (!deadline.isCompleted) deadline.complete();
                });
              }
              return parent.createTimer(zone, duration, callback);
            },
          ),
        );
        final task = queue.queue.single;
        expect(task.status, cancel ? TaskStatus.cancelled : TaskStatus.completed);
        expect(requests, 1);
        expect(saved, cancel ? 0 : 1);
        expect(rows.length, cancel ? 0 : 1);
        if (!cancel) {
          expect(task.resultPaths, hasLength(1));
          expect(await File(task.resultPaths.single).readAsBytes(), png);
          expect(rows.single.outputTokens, 7);
          expect((await db.getRecentTasks(20)).single.resultPaths, task.resultPaths);
        } else {
          expect(task.resultPaths, isEmpty);
        }
      });
    }
  }
}
