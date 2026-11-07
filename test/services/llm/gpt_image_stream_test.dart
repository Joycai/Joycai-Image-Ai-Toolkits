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
    'leadingWhitespace',
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
        if (mode == 'leadingWhitespace') r.response.write('\n \t\r\n\t\n');
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
      if (mode == 'wrapped') {
        expect(log, contains('Compatibility: joined wrapped data lines'));
      } else if (mode == 'multiline') {
        expect(log, isNot(contains('Compatibility: joined wrapped data lines')));
      }
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

  for (final mode in [
    'url',
    'messageUrl',
    'messageProgressError',
    'namedPreviewEmptyType',
    'namedErrorEmptyType',
    'namedErrorConflictingType',
    'base64',
    'progressErrorThenSuccess',
    'statusOnly',
    'progressErrorOnly',
    'failed',
    'cancelled',
    'genericError',
    'typedError',
    'unknownPreview',
    'progressImage',
    'invalidDownload',
    'emptyResult',
  ]) {
    test('relay SSE $mode preserves delivery and error boundaries', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var posts = 0;
      var downloads = 0;
      server.listen((r) async {
        if (r.uri.path == '/image') {
          downloads++;
          expect(r.headers.value('authorization'), isNull);
          r.response.add(mode == 'invalidDownload' ? utf8.encode('<html>unavailable</html>') : png);
          await r.response.close();
          return;
        }
        posts++;
        await r.drain<void>();
        r.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream');
        void event(Map<String, dynamic> data, {String? name}) {
          if (name != null || mode.startsWith('message')) {
            r.response.write('event: ${name ?? 'message'}\n');
          }
          r.response.write('data: ${jsonEncode(data)}\n\n');
        }

        final result = <String, dynamic>{
          'data': [
            mode == 'base64'
                ? {'b64_json': base64Encode(png)}
                : {'url': 'http://127.0.0.1:${server.port}/image'},
          ],
          'usage': {'input_tokens': 12, 'output_tokens': 34, 'reported_cost_usd': 999},
          'size': '1664x2496',
          'quality': 'auto',
          'output_format': 'png',
        };
        event({'status': 'in_progress', 'progress': 0});
        if (mode.startsWith('progressError') || mode == 'messageProgressError') {
          event({'status': 'in_progress', 'error': 'system under load'});
        }
        switch (mode) {
          case 'namedPreviewEmptyType':
            event({'type': '', ...result}, name: 'vendor.preview');
          case 'namedErrorEmptyType':
            event({
              'type': '',
              'status': 'in_progress',
              'error': 'terminal failure',
            }, name: 'error');
            event(result);
          case 'namedErrorConflictingType':
            event({
              'type': 'image_edit.completed',
              'b64_json': base64Encode(png),
              'message': 'terminal failure',
            }, name: 'image_edit.failed');
          case 'failed':
          case 'cancelled':
            event({'status': mode, 'error': 'terminal failure'});
            event(result);
          case 'genericError':
            event({'error': 'terminal failure'});
            event(result);
          case 'typedError':
            event({'type': 'error', 'status': 'in_progress', 'error': 'terminal failure'});
            event(result);
          case 'unknownPreview':
            event({'type': 'vendor.preview', ...result});
          case 'progressImage':
            event({'status': 'in_progress', ...result});
          case 'statusOnly':
            event({'status': 'completed'});
          case 'progressErrorOnly':
            break;
          case 'emptyResult':
            event({'data': []});
          default:
            event({'status': 'completed', 'progress': 100});
            event(result);
            event(result); // Duplicate result must not save/count twice.
        }
        r.response.write('data: [DONE]\n\n');
        await r.response.flush();
        if ([
          'url',
          'messageUrl',
          'messageProgressError',
          'base64',
          'progressErrorThenSuccess',
          'statusOnly',
        ].contains(mode)) {
          await release.future; // Complete without requiring socket EOF.
        }
        await r.response.close();
      });
      final chunks = <LLMResponseChunk>[];
      final operation = LLMDispatcher()
          .generateStream(
            LLMModelConfig(
              modelId: '[Adobe]gpt-image-2.5-sunburst',
              channelType: Vendors.openAIRest,
              endpoint: 'http://127.0.0.1:${server.port}/v1',
              apiKey: 'test',
            ),
            [LLMMessage(role: LLMRole.user, content: 'circle')],
          )
          .forEach(chunks.add)
          .timeout(const Duration(seconds: 10));
      if ([
        'url',
        'messageUrl',
        'messageProgressError',
        'base64',
        'progressErrorThenSuccess',
      ].contains(mode)) {
        await operation;
        final delivered = chunks.where((c) => c.imagePart != null).single;
        expect(delivered.imagePart, png);
        expect(delivered.metadata!['output_tokens'], 34);
        expect(delivered.metadata!['output_size'], '1664x2496');
        expect(delivered.metadata!['reported_cost_usd'], isNull);
        expect(chunks.where((c) => c.isDone), hasLength(1));
        expect(downloads, mode == 'base64' ? 0 : 1);
      } else {
        final detail = switch (mode) {
          'statusOnly' => 'Provider reported completion without an image',
          'progressErrorOnly' => 'system under load',
          'failed' ||
          'cancelled' ||
          'genericError' ||
          'typedError' ||
          'namedErrorEmptyType' ||
          'namedErrorConflictingType' => 'terminal failure',
          'invalidDownload' => 'no valid image could be retrieved',
          'emptyResult' => 'no image references',
          _ => 'stream ended before the final image',
        };
        await expectLater(
          operation,
          throwsA(isA<LLMApiException>().having((e) => e.toString(), 'detail', contains(detail))),
        );
        expect(chunks.where((c) => c.imagePart != null), isEmpty);
        if (mode != 'invalidDownload') expect(downloads, 0);
      }
      expect(posts, 1);
      release.complete();
    });
  }

  for (final prefix in ['image_generation', 'image_edit']) {
    test('$prefix URL previews stay transient and URL completion delivers once', () async {
      LLMDebugLogger.enabled = true;
      addTearDown(() => LLMDebugLogger.enabled = false);
      final correlation = LLMLogCorrelation(contextId: 'download', request: 1, leg: 0, attempt: 0);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var posts = 0;
      var downloads = 0;
      server.listen((r) async {
        if (r.method == 'GET') {
          downloads++;
          expect(r.headers.value('authorization'), isNull);
          r.response.add(png);
          await r.response.close();
          return;
        }
        posts++;
        await r.drain<void>();
        r.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream');
        void event(String suffix) => r.response.write(
          'event: $prefix.$suffix\ndata: ${jsonEncode({
            'type': '$prefix.$suffix',
            'created_at': 1793782347,
            if (prefix == 'image_edit') 'b64_json': '',
            'url': 'http://127.0.0.1:${server.port}/image',
            if (suffix == 'completed') 'usage': {'input_tokens': 3451, 'output_tokens': 1054},
          })}\n\n',
        );
        event('partial_image');
        await r.response.flush();
        await release.future;
        event('completed');
        await r.response.close();
      });
      final preview = Completer<void>();
      final chunks = <LLMResponseChunk>[];
      final operation =
          LLMDebugLogger.correlatedStream(
            correlation,
            () => LLMDispatcher().generateStream(
              LLMModelConfig(
                modelId: '[Adobe]gpt-image-2.5-sunburst',
                channelType: Vendors.openAIRest,
                endpoint: 'http://127.0.0.1:${server.port}/v1',
                apiKey: 'test',
              ),
              [LLMMessage(role: LLMRole.user, content: 'circle')],
            ),
          ).forEach((chunk) {
            chunks.add(chunk);
            if (chunk.imagePreview != null && !preview.isCompleted) preview.complete();
          });
      // Await either preview or failure so a regression reports promptly.
      await Future.any([preview.future, operation]).timeout(const Duration(seconds: 10));
      expect(chunks.where((c) => c.imagePart != null), isEmpty);
      expect(chunks.single.imagePreview, png);
      release.complete();
      await operation.timeout(const Duration(seconds: 10));
      final delivered = chunks.where((c) => c.imagePart != null).single;
      expect(delivered.imagePart, png);
      expect(delivered.metadata!['output_tokens'], 1054);
      expect(chunks.where((c) => c.isDone), hasLength(1));
      expect(posts, 1);
      expect(downloads, 2);
      final log = await correlation.opened.single.file.readAsString();
      expect(log, contains('Image retrieval starting:'));
      expect(log, contains('final=true carrier=url'));
      expect(log, contains('Download headers: attempt=1 status=200'));
      expect(log, contains('detectedMime=image/png'));
    });
  }

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
