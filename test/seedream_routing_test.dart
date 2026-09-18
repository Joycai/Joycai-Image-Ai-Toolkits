import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Routing for Seedream (Layer 2 + dispatcher): Ark's own channel, relays,
/// endpoint ids, pins, and the single-shot/billing/deadline answers that all
/// hang off the resolved route.
void main() {
  const pro = 'doubao-seedream-5-0-pro-260628';
  const lite = 'doubao-seedream-5.0-lite';

  LLMModelConfig config(String channelType, String modelId,
          {String endpoint = 'https://ark.cn-beijing.volces.com/api/v3',
          String? tag,
          String? wireProtocol}) =>
      LLMModelConfig(
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
          Vendors.volcengineArk, 'ep-20260918-abcde',
          tag: 'image');
      expect(menu.recognized, isFalse);
      expect(menu.options, contains(WireProtocol.arkImages));
      // Pinned, it becomes a Seedream model with the protocol's table.
      final d = LLMDispatcher.descriptorFor(
          channelType: Vendors.volcengineArk,
          modelId: 'ep-20260918-abcde',
          tag: 'image',
          wireProtocol: WireProtocol.arkImages.id);
      expect(d.family, ModelFamily.seedreamImage);
      expect(d.capabilities.isImageGenerator, isTrue);
      expect(d.capabilities.imageParams.map((p) => p.key),
          containsAll(['imageSize', 'aspectRatio', 'watermark']));
    });

    test('pins on a relay re-describe the model into that route', () {
      final chat = LLMDispatcher.descriptorFor(
          channelType: Vendors.newApiOpenAI,
          modelId: lite,
          wireProtocol: WireProtocol.chatImage.id);
      expect(chat.family, ModelFamily.other);
      expect(chat.capabilities.isImageGenerator, isTrue);

      final images = LLMDispatcher.descriptorFor(
          channelType: Vendors.newApiOpenAI,
          modelId: lite,
          wireProtocol: WireProtocol.openaiImages.id);
      expect(images.family, ModelFamily.openaiImage);

      // Pinning auto's own route keeps the precise table.
      final ark = LLMDispatcher.descriptorFor(
          channelType: Vendors.newApiOpenAI,
          modelId: lite,
          wireProtocol: WireProtocol.arkImages.id);
      expect(ark.family, ModelFamily.seedreamImage);
      expect(ark.capabilities.imageParams.map((p) => p.key),
          contains('webSearch'));
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
        expect(dispatcher.streamSupportsTools(c), isFalse,
            reason: c.channelType);
      }
    });

    test('the deadline widens with the images one request may draw', () {
      final c = config(Vendors.volcengineArk, lite);
      expect(dispatcher.generateTimeout(c), const Duration(minutes: 5));
      expect(dispatcher.generateTimeout(c, options: {'maxImages': '1'}),
          const Duration(minutes: 5));
      expect(dispatcher.generateTimeout(c, options: {'maxImages': '4'}),
          const Duration(minutes: 7));
      expect(dispatcher.generateTimeout(c, options: {'maxImages': '15'}),
          const Duration(minutes: 14, seconds: 20));
      expect(
          dispatcher.generateTimeout(config(Vendors.volcengineArk, pro),
              options: {'imageTask': 'layers'}),
          const Duration(minutes: 15));
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
        request.response.write(jsonEncode({
          'model': 'doubao-seedream-5-0-lite',
          'created': 1,
          'data': [
            {'url': '$base/img/1.png', 'size': '2848x1600'},
            {
              'error': {
                'code': 'OutputImageSensitiveContentDetected',
                'message': 'blocked',
              },
            },
            {'url': '$base/img/2.png', 'size': '2848x1600'},
          ],
          'usage': {'generated_images': 2, 'output_tokens': 35600},
        }));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('Ark channel: POST {base}/images/generations with Ark\'s body',
        () async {
      final response = await LLMDispatcher().generate(
        config(Vendors.volcengineArk, lite,
            endpoint: 'http://127.0.0.1:${server.port}/api/plan/v3'),
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
        config(Vendors.newApiOpenAI, lite,
            endpoint: 'http://127.0.0.1:${server.port}/v1'),
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
}

/// A 1×1 transparent PNG — enough for the byte-sniffing download check.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
