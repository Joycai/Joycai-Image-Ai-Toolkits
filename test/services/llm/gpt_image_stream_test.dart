import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  for (final id in [
    'gpt-image-2',
    'gpt-image-2-2026-04-21',
    'gpt-image-2.5-flare',
    'gpt-image-2.5-flare-2026-09-08',
    'gpt-image-2.5-sunburst',
    'gpt-image-2.5-sunburst-2026-09-08',
  ]) {
    for (final refs in [0, 1, 2]) {
      test('$id streams $refs-reference previews before final output', () async {
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        String? body;
        String? path;
        server.listen((r) async {
          body = await latin1.decoder.bind(r).join();
          path = r.uri.path;
          r.response
            ..bufferOutput = false
            ..headers.contentType = ContentType('text', 'event-stream');
          final prefix = refs == 0 ? 'image_generation' : 'image_edit';
          void event(String suffix, {bool usage = false}) => r.response.write(
            'event: $prefix.$suffix\r\ndata: ${jsonEncode({
              'type': '$prefix.$suffix',
              'b64_json': base64Encode(png),
              if (usage) ...{
                'usage': {'input_tokens': 12, 'output_tokens': 34, 'total_tokens': 46},
                'size': '1536x864',
                'quality': 'high',
                'output_format': 'png',
              },
            })}\r\n\r\n',
          );
          event('partial_image');
          await r.response.flush();
          await release.future;
          event('partial_image');
          event('completed', usage: true);
          await r.response.close();
        });
        final config = LLMModelConfig(
          modelId: id,
          channelType: Vendors.openAIRest,
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test',
        );
        final dispatcher = LLMDispatcher();
        expect(dispatcher.streamIsSingleShot(config), isFalse);
        expect(dispatcher.imageStreamChunkGap(config), dispatcher.generateTimeout(config));
        final preview = Completer<void>();
        final chunks = <LLMResponseChunk>[];
        final done = dispatcher
            .generateStream(
              config,
              [
                LLMMessage(
                  role: LLMRole.user,
                  content: 'tree',
                  attachments: [
                    for (var i = 0; i < refs; i++) LLMAttachment.fromBytes(png, 'image/png'),
                  ],
                ),
              ],
              options: {'imageSize': '1536x864', 'outputFormat': 'png'},
            )
            .forEach((c) {
              chunks.add(c);
              if (c.imagePreview != null && !preview.isCompleted) preview.complete();
            });
        await preview.future.timeout(const Duration(seconds: 10));
        expect(chunks.where((c) => c.imagePart != null), isEmpty);
        expect(chunks.first.imagePreview, png);
        release.complete();
        await done;
        expect(chunks.where((c) => c.imagePreview != null), hasLength(2));
        expect(chunks.where((c) => c.imagePart != null).single.imagePart, png);
        final metadata = chunks.firstWhere((c) => c.metadata != null).metadata!;
        expect(metadata['output_tokens'], 34);
        expect(metadata['output_size'], '1536x864');
        expect(chunks.last.isDone, isTrue);
        expect(path, refs == 0 ? '/v1/images/generations' : '/v1/images/edits');
        if (refs == 0) {
          expect(jsonDecode(body!)['stream'], true);
          expect(jsonDecode(body!)['partial_images'], 3);
        } else {
          expect(body, contains('name="stream"\r\n\r\ntrue'));
          expect(body, contains('name="partial_images"\r\n\r\n3'));
          expect(body, contains(refs == 1 ? 'name="image";' : 'name="image[]";'));
        }
      });
    }
  }

  for (final mode in ['json', 'empty', 'error', 'malformed', 'previewOnly', 'finalOnly']) {
    test('stream handles $mode without resubmitting', () async {
      var requests = 0;
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        requests++;
        r.response.bufferOutput = false;
        await r.drain<void>();
        r.response.headers.contentType = mode == 'json'
            ? ContentType.json
            : ContentType('text', 'event-stream');
        if (mode == 'json') {
          r.response.write(
            jsonEncode({
              'data': [
                {'b64_json': base64Encode(png)},
              ],
            }),
          );
        } else if (mode == 'error') {
          r.response.write('data: {"error":{"message":"blocked"}}\n\n');
        } else if (mode == 'malformed') {
          r.response.write('data: {broken\n\n');
        } else if (mode == 'previewOnly' || mode == 'finalOnly') {
          r.response.write(
            'data: ${jsonEncode({'type': mode == 'finalOnly' ? 'image_generation.completed' : 'image_generation.partial_image', 'b64_json': base64Encode(png)})}\n\n',
          );
        }
        if (mode == 'finalOnly') {
          await r.response.flush();
          await release.future;
        }
        await r.response.close();
      });
      final stream = LLMDispatcher().generateStream(
        LLMModelConfig(
          modelId: 'gpt-image-2',
          channelType: Vendors.openAIRest,
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          apiKey: 'test',
        ),
        [LLMMessage(role: LLMRole.user, content: 'tree')],
      );
      if (mode == 'json' || mode == 'finalOnly') {
        expect(
          (await stream.toList().timeout(const Duration(seconds: 10)))
              .where((c) => c.imagePart != null),
          hasLength(1),
        );
      } else {
        await expectLater(stream.drain<void>(), throwsA(isA<LLMApiException>()));
      }
      release.complete();
      expect(requests, 1);
    });
  }

  test('earlier image models keep single-shot streaming adapter', () {
    expect(
      LLMDispatcher().streamIsSingleShot(
        LLMModelConfig(
          modelId: 'gpt-image-1',
          channelType: Vendors.openAIRest,
          endpoint: 'http://localhost/v1',
          apiKey: 'test',
        ),
      ),
      true,
    );
  });
}
