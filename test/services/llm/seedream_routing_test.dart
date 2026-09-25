import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/image_layer.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Routing for Seedream (Layer 2 + dispatcher): Ark's own channel, relays,
/// endpoint ids, pins, and the single-shot/billing/deadline answers that all
/// hang off the resolved route.
void main() {
  const pro = 'doubao-seedream-5-0-pro-260628';
  const lite = 'doubao-seedream-5.0-lite';

  LLMModelConfig config(
    String channelType,
    String modelId, {
    String endpoint = 'https://ark.cn-beijing.volces.com/api/v3',
    String? tag,
    String? wireProtocol,
  }) => LLMModelConfig(
    modelId: modelId,
    channelType: channelType,
    endpoint: endpoint,
    apiKey: 'k',
    tag: tag,
    wireProtocol: wireProtocol,
  );

  group('menus and auto', () {
    test('on Ark: one route, Ark images, auto', () {
      final menu = LLMDispatcher.protocolMenu(Vendors.volcengineArk, pro);
      expect(menu.surface, Surface.imageGen);
      expect(menu.options, [WireProtocol.arkImages]);
      expect(menu.auto, WireProtocol.arkImages);
      expect(menu.recognized, isTrue);
    });

    test('on a relay: Ark body leads, the generic surfaces stay pinnable', () {
      for (final relay in [Vendors.newApiOpenAI, Vendors.openAIRest]) {
        final menu = LLMDispatcher.protocolMenu(relay, lite);
        expect(menu.options, [
          WireProtocol.arkImages,
          WireProtocol.openaiImages,
          WireProtocol.chatImage,
        ], reason: relay);
        expect(menu.auto, WireProtocol.arkImages, reason: relay);
      }
    });

    test('a first-party ① vendor without generic surfaces still gets auto', () {
      final menu = LLMDispatcher.protocolMenu(Vendors.deepseek, lite);
      expect(menu.options, [WireProtocol.arkImages]);
    });

    test('Ark endpoint id tagged image: unrecognized, Ark pinnable', () {
      final menu = LLMDispatcher.protocolMenu(
        Vendors.volcengineArk,
        'ep-20260918-abcde',
        tag: 'image',
      );
      expect(menu.recognized, isFalse);
      expect(menu.options, contains(WireProtocol.arkImages));
      // Pinned, it becomes a Seedream model with the protocol's table.
      final d = LLMDispatcher.descriptorFor(
        channelType: Vendors.volcengineArk,
        modelId: 'ep-20260918-abcde',
        tag: 'image',
        wireProtocol: WireProtocol.arkImages.id,
      );
      expect(d.family, ModelFamily.seedreamImage);
      expect(d.capabilities.isImageGenerator, isTrue);
      expect(
        d.capabilities.imageParams.map((p) => p.key),
        containsAll(['imageSize', 'aspectRatio', 'watermark']),
      );
    });

    test('pins on a relay re-describe the model into that route', () {
      final chat = LLMDispatcher.descriptorFor(
        channelType: Vendors.newApiOpenAI,
        modelId: lite,
        wireProtocol: WireProtocol.chatImage.id,
      );
      expect(chat.family, ModelFamily.other);
      expect(chat.capabilities.isImageGenerator, isTrue);

      final images = LLMDispatcher.descriptorFor(
        channelType: Vendors.newApiOpenAI,
        modelId: lite,
        wireProtocol: WireProtocol.openaiImages.id,
      );
      expect(images.family, ModelFamily.openaiImage);

      // Pinning auto's own route keeps the precise table.
      final ark = LLMDispatcher.descriptorFor(
        channelType: Vendors.newApiOpenAI,
        modelId: lite,
        wireProtocol: WireProtocol.arkImages.id,
      );
      expect(ark.family, ModelFamily.seedreamImage);
      expect(ark.capabilities.imageParams.map((p) => p.key), contains('webSearch'));
    });
  });

  group('route answers', () {
    final dispatcher = LLMDispatcher();

    test('single-shot, billed on submit, no tools — on Ark and relays', () {
      for (final c in [
        config(Vendors.volcengineArk, pro),
        config(Vendors.newApiOpenAI, lite, endpoint: 'https://relay/v1'),
      ]) {
        expect(dispatcher.streamIsSingleShot(c), isTrue, reason: c.channelType);
        expect(dispatcher.isBilledOnSubmit(c), isTrue, reason: c.channelType);
        expect(dispatcher.streamSupportsTools(c), isFalse, reason: c.channelType);
      }
    });

    test('the deadline widens with the images one request may draw', () {
      final c = config(Vendors.volcengineArk, lite);
      expect(dispatcher.generateTimeout(c), const Duration(minutes: 5));
      expect(
        dispatcher.generateTimeout(c, options: {'maxImages': '1'}),
        const Duration(minutes: 5),
      );
      expect(
        dispatcher.generateTimeout(c, options: {'maxImages': '4'}),
        const Duration(minutes: 7),
      );
      expect(
        dispatcher.generateTimeout(c, options: {'maxImages': '15'}),
        const Duration(minutes: 14, seconds: 20),
      );
      expect(
        dispatcher.generateTimeout(
          config(Vendors.volcengineArk, pro),
          options: {'imageTask': 'layers'},
        ),
        const Duration(minutes: 15),
      );
    });
  });

  group('on the wire', () {
    late HttpServer server;
    late List<(String path, Map<String, dynamic> body, String? auth)> seen;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      seen = [];
      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(_png);
          await request.response.close();
          return;
        }
        final raw = await utf8.decodeStream(request);
        seen.add((
          request.uri.path,
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
          request.headers.value('authorization'),
        ));
        request.response.headers.contentType = ContentType.json;
        final base = 'http://127.0.0.1:${server.port}';
        request.response.write(
          jsonEncode({
            'model': 'doubao-seedream-5-0-lite',
            'created': 1,
            'data': [
              {'url': '$base/img/1.png', 'size': '2848x1600'},
              {
                'error': {'code': 'OutputImageSensitiveContentDetected', 'message': 'blocked'},
              },
              {'url': '$base/img/2.png', 'size': '2848x1600'},
            ],
            'usage': {'generated_images': 2, 'output_tokens': 35600},
          }),
        );
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('Ark channel: POST {base}/images/generations with Ark\'s body', () async {
      final response = await LLMDispatcher().generate(
        config(
          Vendors.volcengineArk,
          lite,
          endpoint: 'http://127.0.0.1:${server.port}/api/plan/v3',
        ),
        [
          LLMMessage(
            role: LLMRole.user,
            content: 'two posters',
            attachments: [LLMAttachment.fromBytes(_png, 'image/png')],
          ),
        ],
        options: {
          'imageSize': '2K',
          'aspectRatio': '16:9',
          'maxImages': '3',
          'outputFormat': 'png',
          'webSearch': 'off',
          'watermark': 'off',
        },
      );

      final (path, body, auth) = seen.single;
      expect(path, '/api/plan/v3/images/generations');
      expect(auth, 'Bearer k');
      expect(body['model'], lite);
      expect(body['size'], '2848x1600');
      expect(body['image'], startsWith('data:image/png;base64,'));
      expect(body['sequential_image_generation'], 'auto');
      expect(body['sequential_image_generation_options'], {'max_images': 3});
      expect(body['watermark'], isFalse);
      expect(body['output_format'], 'png');
      expect(body['response_format'], 'url');
      expect(body.containsKey('tools'), isFalse);

      // Two delivered, the moderated one reported but not fatal; usage kept
      // off the token keys.
      expect(response.generatedImages, hasLength(2));
      expect(response.metadata['image_count'], 2);
      expect(response.metadata['failed_images'], 1);
      expect(response.metadata.containsKey('output_tokens'), isFalse);
      expect(response.metadata['ark_usage'], isA<Map>());
    });

    test('relay: the same body at the relay\'s Images path', () async {
      await LLMDispatcher().generate(
        config(Vendors.newApiOpenAI, lite, endpoint: 'http://127.0.0.1:${server.port}/v1'),
        [LLMMessage(role: LLMRole.user, content: 'a poster')],
        options: {'imageSize': '2K', 'watermark': 'off'},
      );
      final (path, body, _) = seen.single;
      expect(path, '/v1/images/generations');
      expect(body['size'], '2K');
      expect(body['watermark'], isFalse);
      expect(body.containsKey('n'), isFalse, reason: 'Ark body, not OpenAI\'s');
    });
  });

  group('live image stream', () {
    final dispatcher = LLMDispatcher();

    test('lite on Ark streams live; pro and relays stay single-shot', () {
      final live = config(Vendors.volcengineArk, lite);
      expect(dispatcher.streamIsSingleShot(live), isFalse);
      expect(dispatcher.imageStreamChunkGap(live), const Duration(minutes: 5));
      expect(
        dispatcher.isBilledOnSubmit(live),
        isTrue,
        reason: 'still a billed generation: no retry after acceptance',
      );
      expect(dispatcher.streamSupportsTools(live), isFalse);

      for (final c in [
        config(Vendors.volcengineArk, pro),
        config(Vendors.newApiOpenAI, lite, endpoint: 'https://relay/v1'),
      ]) {
        expect(dispatcher.imageStreamChunkGap(c), isNull, reason: c.channelType);
        expect(dispatcher.streamIsSingleShot(c), isTrue, reason: c.channelType);
      }
    });

    late HttpServer server;
    late List<Map<String, dynamic>> bodies;
    // What the POST answers: 'sse', 'sse-gone', 'sse-octet', 'json', or
    // 'error'.
    late String answer;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bodies = [];
      answer = 'sse';
      server.listen((request) async {
        if (request.method == 'GET') {
          if (request.uri.path.contains('gone')) {
            request.response.statusCode = 404;
          } else {
            request.response.headers.contentType = ContentType('image', 'png');
            request.response.add(_png);
          }
          await request.response.close();
          return;
        }
        bodies.add((jsonDecode(await utf8.decodeStream(request)) as Map).cast<String, dynamic>());
        final base = 'http://127.0.0.1:${server.port}';
        switch (answer) {
          case 'error':
            request.response.statusCode = 400;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'error': {
                  'code': 'InvalidParameter',
                  'message': 'size is invalid',
                  'param': 'size',
                  'type': 'BadRequest',
                },
              }),
            );
          case 'layers':
            // A decomposition, out of order, whose middle layer's link is
            // dead: the survivors must keep their own layer records.
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'data': [
                  {
                    'url': '$base/img/top.png',
                    'z_index': 2,
                    'name': 'top',
                    'bounding_box': {
                      'absolute': [10, 20, 30, 40],
                    },
                  },
                  {'url': '$base/img/base.png', 'z_index': 0},
                  {
                    'url': '$base/gone/mid.png',
                    'z_index': 1,
                    'name': 'mid',
                    'bounding_box': {
                      'absolute': [0, 0, 5, 5],
                    },
                  },
                ],
                'usage': {'generated_images': 3},
              }),
            );
          case 'json':
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'data': [
                  {'url': '$base/img/1.png'},
                ],
                'usage': {'generated_images': 1},
              }),
            );
          default:
            // 'sse-gone': links that 404 when fetched.
            final dir = answer == 'sse-gone' ? 'gone' : 'img';
            // 'sse-octet': SSE under a Content-Type that does not say so.
            request.response.headers.contentType = answer == 'sse-octet'
                ? ContentType('application', 'octet-stream')
                : ContentType('text', 'event-stream');
            void event(Map<String, dynamic> data) {
              request.response
                ..write('event: ${data['type']}\n')
                ..write('data: ${jsonEncode(data)}\n\n');
            }

            event({
              'type': 'image_generation.partial_succeeded',
              'image_index': 0,
              'url': '$base/$dir/0.png',
              'size': '2496x1664',
            });
            await request.response.flush();
            event({
              'type': 'image_generation.partial_failed',
              'image_index': 1,
              'error': {'code': 'OutputImageSensitiveContentDetected', 'message': 'blocked'},
            });
            event({
              'type': 'image_generation.partial_succeeded',
              'image_index': 2,
              'url': '$base/$dir/2.png',
              'size': '2496x1664',
            });
            event({
              'type': 'image_generation.completed',
              'usage': {'generated_images': 2, 'output_tokens': 32448},
            });
            request.response.write('data: [DONE]\n\n');
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    LLMModelConfig ark() => config(
      Vendors.volcengineArk,
      lite,
      endpoint: 'http://127.0.0.1:${server.port}/api/plan/v3',
    );

    Future<List<LLMResponseChunk>> run(LLMModelConfig c) => dispatcher
        .generateStream(
          c,
          [LLMMessage(role: LLMRole.user, content: 'two')],
          options: {'maxImages': '3', 'watermark': 'off'},
        )
        .toList();

    test('each image arrives as its own chunk; failures and usage at the end', () async {
      final chunks = await run(ark());
      expect(bodies.single['stream'], isTrue);
      final images = chunks.where((c) => c.imagePart != null).toList();
      expect(images, hasLength(2));
      final last = chunks.last;
      expect(last.isDone, isTrue);
      expect(last.metadata?['image_count'], 2);
      expect(last.metadata?['failed_images'], 1);
      expect(last.metadata?['ark_usage'], {'generated_images': 2, 'output_tokens': 32448});
      expect(last.metadata?.containsKey('output_tokens'), isFalse);
    });

    test('the closing chunk says how many references the stream request carried', () async {
      final chunks = await dispatcher.generateStream(ark(), [
        LLMMessage(
          role: LLMRole.user,
          content: 'two',
          attachments: [
            LLMAttachment.fromBytes(_png, 'image/png'),
            LLMAttachment.fromBytes(_png, 'image/png'),
          ],
        ),
      ]).toList();
      expect(chunks.last.metadata?[inputImageCountKey], 2);
      // And a text-to-image stream says nothing.
      expect((await run(ark())).last.metadata?.containsKey(inputImageCountKey), isFalse);
    });

    test('SSE is recognised by its body, whatever the Content-Type says', () async {
      answer = 'sse-octet';
      final chunks = await run(ark());
      expect(chunks.where((c) => c.imagePart != null), hasLength(2));
      expect(chunks.last.metadata?['image_count'], 2);
    });

    test('a JSON answer to a stream request is read as the synchronous one', () async {
      answer = 'json';
      final chunks = await run(ark());
      expect(chunks.where((c) => c.imagePart != null), hasLength(1));
      expect(chunks.last.metadata?['image_count'], 1);
    });

    test('a parameter error is the plain 400 envelope, not an event', () async {
      answer = 'error';
      await expectLater(
        run(ark()),
        throwsA(
          isA<LLMApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.message, 'message', contains('size is invalid')),
        ),
      );
    });

    test('links that all fail to download fail the request', () async {
      answer = 'sse-gone';
      await expectLater(
        run(ark()),
        throwsA(
          isA<LLMApiException>().having((e) => e.message, 'message', contains('none of which')),
        ),
      );
    });

    test('a decomposition keeps each image paired with its layer', () async {
      answer = 'layers';
      final c = config(
        Vendors.volcengineArk,
        pro,
        endpoint: 'http://127.0.0.1:${server.port}/api/plan/v3',
      );
      final history = [LLMMessage(role: LLMRole.user, content: 'split')];

      final whole = await dispatcher.generate(c, history, options: {'watermark': 'off'});
      expect(whole.generatedImages, hasLength(2));
      expect([for (final l in whole.imageLayers) l?.zIndex], [0, 2]);
      expect(whole.imageLayers.last!.name, 'top');
      expect(whole.imageLayers.last!.box, const LayerBox(10, 20, 30, 40));

      // 5.0 pro never streams live; the single-shot stream still carries
      // the pairing on each image chunk.
      final chunks = await dispatcher
          .generateStream(c, history, options: {'watermark': 'off'})
          .where((ch) => ch.imagePart != null)
          .toList();
      expect([for (final ch in chunks) ch.imageLayer?.zIndex], [0, 2]);
    });

    test('ordinary images carry no layer', () async {
      final chunks = await run(ark());
      expect(chunks.where((c) => c.imageLayer != null), isEmpty);
    });

    test('a relay gets the synchronous body — no `stream`', () async {
      answer = 'json';
      await run(config(Vendors.newApiOpenAI, lite, endpoint: 'http://127.0.0.1:${server.port}/v1'));
      expect(bodies.single.containsKey('stream'), isFalse);
    });
  });
}

/// A 1×1 transparent PNG — enough for the byte-sniffing download check.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
