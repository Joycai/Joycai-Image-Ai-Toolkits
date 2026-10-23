import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_debug_logger.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

import '../../support/private_data_dir.dart';

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  usePrivateDataDir('gpt_stream_compat');
  setUpAll(() => HttpOverrides.global = null);
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

  for (final mode in [
    'json',
    'jsonAsSse',
    'empty',
    'error',
    'malformed',
    'previewOnly',
    'finalOnly',
  ]) {
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
        if (mode == 'json' || mode == 'jsonAsSse') {
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
      if (mode == 'json' || mode == 'jsonAsSse' || mode == 'finalOnly') {
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

  for (final mode in [
    'missingSeparators',
    'wrapped',
    'multiline',
    'wrongHeader',
    'bom',
    'truncated',
    'invalid',
  ]) {
    test('gateway compatibility and diagnostics: $mode', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var requests = 0;
      final encoded = base64Encode(png);
      final partial = jsonEncode({'type': 'image_edit.partial_image', 'b64_json': encoded});
      var finalEvent = jsonEncode({
        'type': 'image_edit.completed',
        'b64_json': encoded,
        'usage': {'input_tokens': 7, 'output_tokens': 11},
        'size': '1024x1024',
        'padding': 'x' * 4096,
      });
      server.listen((r) async {
        requests++;
        await r.drain<void>();
        r.response
          ..bufferOutput = false
          ..headers.contentType = mode == 'wrongHeader'
              ? ContentType.json
              : ContentType('text', 'event-stream');
        if (mode == 'bom') r.response.add(utf8.encode('\uFEFF: keepalive\r\n'));
        if (mode == 'missingSeparators') r.response.write('data: $partial\n');
        if (mode == 'wrapped') {
          finalEvent = finalEvent.replaceFirst(
            encoded,
            '${encoded.substring(0, 40)}\ndata: ${encoded.substring(40)}',
          );
        } else if (mode == 'multiline') {
          finalEvent = finalEvent.replaceFirst(',"b64_json"', ',\ndata: "b64_json"');
        } else if (mode == 'truncated') {
          finalEvent = finalEvent.substring(0, finalEvent.length - 2);
        } else if (mode == 'invalid') {
          finalEvent += '}';
        }
        r.response.write('data: $finalEvent\n');
        if (mode == 'invalid' || mode == 'truncated') {
          await r.response.close();
        } else {
          await r.response.flush();
          await release.future;
          await r.response.close();
        }
      });
      final correlation = LLMLogCorrelation(contextId: 'compat', request: 1, leg: 0, attempt: 0);
      LLMDebugLogger.enabled = true;
      addTearDown(() => LLMDebugLogger.enabled = false);
      final stream = LLMDebugLogger.correlatedStream(
        correlation,
        () => LLMDispatcher().generateStream(
          LLMModelConfig(
            modelId: 'gpt-image-2.5-sunburst',
            channelType: Vendors.openAIRest,
            endpoint: 'http://127.0.0.1:${server.port}/v1',
            apiKey: 'test-secret',
          ),
          [
            LLMMessage(
              role: LLMRole.user,
              content: 'tree',
              attachments: [LLMAttachment.fromBytes(png, 'image/png')],
            ),
          ],
        ),
      );
      if (mode == 'invalid' || mode == 'truncated') {
        await expectLater(
          stream.drain<void>(),
          throwsA(
            isA<LLMApiException>().having(
              (e) => e.toString(),
              'diagnostic',
              allOf(contains('offset='), contains('dataLines='), isNot(contains('HTML'))),
            ),
          ),
        );
      } else {
        final chunks = await stream.toList().timeout(const Duration(seconds: 10));
        expect(chunks.where((c) => c.imagePart != null).single.imagePart, png);
        expect(chunks.firstWhere((c) => c.imagePart != null).metadata!['output_tokens'], 11);
        if (mode == 'missingSeparators') expect(chunks.first.imagePreview, png);
      }
      release.complete();
      expect(requests, 1);
      final log = await correlation.opened.single.file.readAsString();
      expect(log, contains('status=200'));
      expect(log, contains('Detected format: SSE'));
      expect(log, contains('image_edit.completed'));
      expect(log, isNot(contains('x' * 4096)));
      expect(log, isNot(contains('test-secret')));
      expect(log, contains('Elapsed:'));
      if (mode == 'invalid' || mode == 'truncated') {
        expect(log, contains('Stream failure:'));
        expect(log, contains('codeUnit='));
      }
    });
  }

  test('large wrapped image completes promptly without a separator or disconnect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    // The resolver validates the image signature; pad the fixture to exercise
    // a realistic base64 payload without adding a large binary test asset.
    final bytes = [...png, ...List<int>.filled(768 * 1024, 0)];
    final payload = jsonEncode({
      'type': 'image_generation.completed',
      'b64_json': base64Encode(bytes),
    });
    final wire = StringBuffer();
    for (var start = 0; start < payload.length; start += 76) {
      final end = start + 76 < payload.length ? start + 76 : payload.length;
      wire.writeln('data: ${payload.substring(start, end)}');
    }
    var requests = 0;
    server.listen((r) async {
      requests++;
      await r.drain<void>();
      r.response
        ..bufferOutput = false
        ..headers.contentType = ContentType('text', 'event-stream')
        ..write(wire);
      await r.response.flush();
      await release.future;
      await r.response.close();
    });
    final watch = Stopwatch()..start();
    final chunks = await LLMDispatcher()
        .generateStream(
          LLMModelConfig(
            modelId: 'gpt-image-2',
            channelType: Vendors.openAIRest,
            endpoint: 'http://127.0.0.1:${server.port}/v1',
            apiKey: 'test',
          ),
          [LLMMessage(role: LLMRole.user, content: 'tree')],
        )
        .toList()
        .timeout(const Duration(seconds: 5));
    watch.stop();
    // Also measure elapsed time: synchronous decoding can starve timeout timers.
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(chunks.where((c) => c.imagePart != null).single.imagePart, bytes);
    expect(chunks.last.isDone, isTrue);
    expect(requests, 1);
    release.complete();
  });

  for (final fails in [false, true]) {
    test('non-streaming image logs elapsed time on ${fails ? 'error' : 'success'}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        await r.drain<void>();
        r.response
          ..headers.contentType = ContentType.json
          ..statusCode = fails ? 400 : 200
          ..write(
            jsonEncode(
              fails
                  ? {
                      'error': {'message': 'blocked'},
                    }
                  : {
                      'data': [
                        {'b64_json': base64Encode(png)},
                      ],
                    },
            ),
          );
        await r.response.close();
      });
      LLMDebugLogger.enabled = true;
      addTearDown(() => LLMDebugLogger.enabled = false);
      final correlation = LLMLogCorrelation(contextId: 'elapsed', request: 1, leg: 0, attempt: 0);
      final response = LLMDebugLogger.runCorrelated(
        correlation,
        () => LLMDispatcher().generate(
          LLMModelConfig(
            modelId: 'gpt-image-2',
            channelType: Vendors.openAIRest,
            endpoint: 'http://127.0.0.1:${server.port}/v1',
            apiKey: 'test',
          ),
          [LLMMessage(role: LLMRole.user, content: 'tree')],
        ),
      );
      if (fails) {
        await expectLater(response, throwsA(isA<LLMApiException>()));
      } else {
        expect((await response).generatedImages.single, png);
      }
      final log = await correlation.opened.single.file.readAsString();
      expect(RegExp(r'Elapsed: \d+ ms').allMatches(log), hasLength(1));
      expect(log.indexOf('Elapsed:'), greaterThan(log.indexOf('Body:')));
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
