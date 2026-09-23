import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/ark_images_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Ark's image transport end to end against a loopback server: the request
/// goes out, the body (JSON or SSE) is read, every link is downloaded, and
/// what the usage row will charge is published.
///
/// The case that matters is the silent one: a picture Ark drew — and billed,
/// by `usage.generated_images` (docs/api/volcengine-ark.md §4) — whose link
/// then fails to download. It is not saved, but it must not be recorded as
/// free either.
void main() {
  // Enough of a PNG for the download check (`imageMimeFromBytes`).
  final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(60, 7)];

  late HttpServer server;
  late String base;
  // What the next POST answers with, and the requests it received.
  late void Function(HttpRequest req, String body) answer;
  final posted = <Map<String, dynamic>>[];

  setUp(() async {
    posted.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      if (req.method == 'GET') {
        if (req.uri.path == '/img/ok.png') {
          req.response.headers.contentType = ContentType('image', 'png');
          req.response.add(png);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
        return;
      }
      final body = await utf8.decodeStream(req);
      posted.add(jsonDecode(body) as Map<String, dynamic>);
      answer(req, body);
    });
  });

  tearDown(() => server.close(force: true));

  LLMTarget target(String modelId) {
    final config = LLMModelConfig(
      modelId: modelId,
      channelType: Vendors.volcengineArk,
      endpoint: '$base/api/v3',
      apiKey: 'k',
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(modelId),
    );
  }

  final prompt = [LLMMessage(role: LLMRole.user, content: 'two apples')];

  void json(HttpRequest req, Object body, {int status = 200}) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    req.response.close();
  }

  void sse(HttpRequest req, List<Map<String, dynamic>> events) {
    req.response.headers.contentType = ContentType('text', 'event-stream');
    for (final e in events) {
      req.response.write('event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n');
    }
    req.response.write('data: [DONE]\n\n');
    req.response.close();
  }

  group('synchronous', () {
    test('a link that fails to download is still charged', () async {
      answer = (req, _) => json(req, {
            'data': [
              {'url': '$base/img/ok.png', 'size': '2048x2048'},
              {'url': '$base/img/gone.png', 'size': '2048x2048'},
            ],
            'usage': {'generated_images': 2, 'output_tokens': 32768},
          });

      final r = await ArkImagesProtocol().generateImage(
          target('doubao-seedream-5-0-lite-260128'), prompt,
          options: const {'maxImages': '2'});

      expect(posted.single['sequential_image_generation'], 'auto');
      expect(r.generatedImages, hasLength(1));
      expect(r.metadata['image_count'], 1);
      expect(r.metadata[billedImageCountKey], 2);

      // …and that is what a per-image group charges.
      final config = LLMModelConfig(
        modelId: 'doubao-seedream-5-0-lite-260128',
        channelType: Vendors.volcengineArk,
        endpoint: base,
        apiKey: 'k',
        billingMode: 'spec',
        outputRates: const [SpecRate(price: 0.22)],
      );
      final usage = LLMService.specUsageFor(config, const {}, r.metadata,
          imageCount: r.generatedImages.length)!;
      expect(usage.units, 2);
      expect(usage.cost, closeTo(0.44, 1e-9));
    });

    group('5.0 pro 「自动」 is priced by what was drawn', () {
      // The pricing page's rows: 2K 0.6 元, 1K and 1.5K both 0.3.
      final proGroup = LLMModelConfig(
        modelId: 'doubao-seedream-5-0-pro-260628',
        channelType: Vendors.volcengineArk,
        endpoint: 'https://x',
        apiKey: 'k',
        billingMode: 'spec',
        outputRates: const [SpecRate(size: '2K', price: 0.6), SpecRate(price: 0.3)],
      );

      Future<(Map<String, dynamic>, double)> run(
          Map<String, dynamic> options, String echoed) async {
        answer = (req, _) => json(req, {
              'data': [
                {'url': '$base/img/ok.png', 'size': echoed},
              ],
              'usage': {'generated_images': 1},
            });
        final r = await ArkImagesProtocol().generateImage(
            target('doubao-seedream-5-0-pro-260628'), prompt,
            options: options);
        final cost = LLMService.specUsageFor(proGroup, options, r.metadata,
                imageCount: r.generatedImages.length)!
            .cost;
        return (r.metadata, cost);
      }

      test('auto + a ratio: upstream\'s 2K pixels, billed 0.6', () async {
        final (meta, cost) =
            await run({'imageSize': 'not_set', 'aspectRatio': '16:9'}, '2816x1584');
        expect(posted.single['size'], '2816x1584');
        expect(meta['output_size'], '2816x1584');
        expect(cost, closeTo(0.6, 1e-9));
      });

      test('a chosen 1.5K keeps its tier, billed 0.3', () async {
        final (meta, cost) =
            await run({'imageSize': '1.5K', 'aspectRatio': '16:9'}, '2048x1152');
        expect(meta.containsKey('output_size'), isFalse);
        expect(cost, closeTo(0.3, 1e-9));
      });
    });

    test('layers with the tier unset go out without a size', () async {
      answer = (req, _) => json(req, {
            'data': [
              {'url': '$base/img/ok.png', 'z_index': 0, 'size': '912x1168'},
              {
                'url': '$base/img/ok.png',
                'z_index': 1,
                'size': '861x1137',
                'name': 'figure',
                'bounding_box': {
                  'absolute': [27, 0, 888, 1137],
                },
              },
            ],
            'usage': {'input_images': 1, 'generated_images': 2},
          });

      final r = await ArkImagesProtocol().generateImage(
        target('doubao-seedream-5-0-pro-260628'),
        [
          LLMMessage(role: LLMRole.user, content: '', attachments: [
            LLMAttachment.fromBytes(Uint8List.fromList(png), 'image/png'),
          ]),
        ],
        options: const {'imageTask': 'layers', 'imageSize': 'not_set'},
      );

      final sent = posted.single;
      expect(sent['layer_decomposition'], isTrue);
      expect(sent.containsKey('size'), isFalse,
          reason: 'upstream\'s `auto`: the source keeps its size');
      expect(sent['image'], startsWith('data:image/png;base64,'));
      expect(r.imageLayers.map((l) => l?.zIndex), [0, 1]);
      expect(r.metadata[billedImageCountKey], 2);
      expect(r.metadata[inputImageCountKey], 1);
      expect(r.metadata.containsKey('output_size'), isFalse,
          reason: 'base and layer differ; the row has one size');
    });

    test('a request with no image at all fails', () async {
      answer = (req, _) => json(req, {
            'data': [
              {
                'error': {
                  'code': 'OutputImageSensitiveContentDetected',
                  'message': 'blocked',
                },
              },
            ],
            'usage': {'generated_images': 0},
          });
      await expectLater(
          ArkImagesProtocol().generateImage(
              target('doubao-seedream-5-0-lite-260128'), prompt),
          throwsA(isA<LLMApiException>().having((e) => e.message, 'message',
              contains('OutputImageSensitiveContentDetected'))));
    });
  });

  group('streamed', () {
    test('each image as it lands; the closing chunk charges what Ark drew',
        () async {
      answer = (req, _) => sse(req, [
            {
              'type': 'image_generation.partial_succeeded',
              'image_index': 0,
              'url': '$base/img/ok.png',
              'size': '2848x1600',
            },
            {
              'type': 'image_generation.partial_succeeded',
              'image_index': 1,
              'url': '$base/img/gone.png',
              'size': '2848x1600',
            },
            {
              'type': 'image_generation.completed',
              'usage': {'generated_images': 2, 'output_tokens': 35600},
            },
          ]);

      final chunks = await ArkImagesProtocol()
          .generateImageStream(target('doubao-seedream-5-0-lite-260128'), prompt,
              options: const {'maxImages': '2'})
          .toList();

      expect(posted.single['stream'], isTrue);
      expect(chunks.where((c) => c.imagePart != null), hasLength(1));
      final closing = chunks.last;
      expect(closing.isDone, isTrue);
      expect(closing.metadata?['image_count'], 1);
      expect(closing.metadata?[billedImageCountKey], 2);
      // No tier chosen: the echo of the picture that arrived is published.
      expect(closing.metadata?['output_size'], '2848x1600');
    });

    test('a stream request answered with one JSON body reads like the '
        'synchronous form', () async {
      answer = (req, _) => json(req, {
            'data': [
              {'url': '$base/img/ok.png'},
            ],
            'usage': {'generated_images': 1},
          });

      final chunks = await ArkImagesProtocol()
          .generateImageStream(target('doubao-seedream-5-0-lite-260128'), prompt)
          .toList();

      expect(chunks.where((c) => c.imagePart != null), hasLength(1));
      expect(chunks.last.isDone, isTrue);
      expect(chunks.last.metadata?[billedImageCountKey], 1);
    });

    test('a 400 envelope fails the stream request with its message', () async {
      answer = (req, _) => json(req, {
            'error': {
              'code': 'InvalidParameter',
              'message': 'size is invalid',
              'param': 'size',
            },
          }, status: 400);

      await expectLater(
          ArkImagesProtocol()
              .generateImageStream(
                  target('doubao-seedream-5-0-lite-260128'), prompt)
              .toList(),
          throwsA(isA<LLMApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)));
    });
  });
}
