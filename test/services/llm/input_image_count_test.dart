import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_images_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// The reference images a request *carried*, as each images protocol
/// publishes them ([inputImageCountKey]) for spec billing to charge.
///
/// What is pinned per protocol is the number that went into the body — after
/// the model's cap and after an attachment that cannot be read was dropped —
/// because a count taken any earlier bills for images nobody received.
void main() {
  late HttpServer server;
  late Map<String, dynamic> Function(HttpRequest request) answer;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'GET' && !request.uri.path.contains('/mj/')) {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(_png);
        await request.response.close();
        return;
      }
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(answer(request)));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  String base() => 'http://127.0.0.1:${server.port}';

  LLMModelConfig config(String channelType, String modelId) => LLMModelConfig(
    modelId: modelId,
    channelType: channelType,
    endpoint: '${base()}/v1',
    apiKey: 'k',
  );

  LLMAttachment readable() => LLMAttachment.fromBytes(_png, 'image/png');
  // Neither a path nor bytes: every protocol drops it while building the body.
  LLMAttachment unreadable() => LLMAttachment.fromBytes(null, 'image/png');

  Future<LLMResponse> generate(LLMModelConfig config, List<LLMAttachment> attachments) =>
      LLMDispatcher().generate(config, [
        LLMMessage(role: LLMRole.user, content: 'merge', attachments: attachments),
      ]);

  final inline = {
    'data': [
      {'b64_json': base64Encode(_png)},
    ],
  };

  test('xAI: capped at the model\'s five, less the one that could not be read', () async {
    answer = (_) => inline;
    final xai = config(Vendors.xaiApi, 'grok-imagine-image');

    final seven = await generate(xai, List.generate(7, (_) => readable()));
    expect(seven.metadata[inputImageCountKey], 5);

    final oneLost = await generate(xai, [readable(), unreadable(), readable()]);
    expect(oneLost.metadata[inputImageCountKey], 2);
  });

  test('text-to-image publishes no count at all', () async {
    answer = (_) => inline;
    final response = await generate(config(Vendors.xaiApi, 'grok-imagine-image'), const []);
    expect(response.metadata.containsKey(inputImageCountKey), isFalse);
  });

  test('OpenAI Images: the files attached to the edit', () async {
    answer = (_) => inline;
    final response = await generate(config(Vendors.openAIRest, 'gpt-image-1'), [
      readable(),
      unreadable(),
      readable(),
    ]);
    expect(response.metadata[inputImageCountKey], 2);
  });

  test('MiniMax: the subject references sent', () async {
    answer = (_) => {
      'data': {
        'image_urls': ['${base()}/img/1.png'],
      },
      'base_resp': {'status_code': 0, 'status_msg': 'success'},
    };
    final minimax = config(Vendors.minimax, 'image-01');

    // image-01 takes one reference: the second is cut before it is read.
    final sent = await generate(minimax, [readable(), readable()]);
    expect(sent.metadata[inputImageCountKey], 1);

    // The cap keeps the first, and the first cannot be read: nothing went.
    final lost = await generate(minimax, [unreadable(), readable()]);
    expect(lost.metadata.containsKey(inputImageCountKey), isFalse);
  });

  group('an upstream block naming the app\'s own keys is not taken at its word', () {
    // The recorder reads both keys for every vendor; a relay could name a
    // field the same. Only a protocol's own conversion may set them
    // (`upstreamUsage`) — the count stays what this client sent.
    const forged = {reportedCostKey: 99.0, inputImageCountKey: 7};

    test('OpenAI Images', () async {
      answer = (_) => {...inline, 'usage': forged};
      final sent = await generate(config(Vendors.openAIRest, 'gpt-image-1'), [readable()]);
      expect(sent.metadata.containsKey(reportedCostKey), isFalse);
      expect(sent.metadata[inputImageCountKey], 1);

      final none = await generate(config(Vendors.openAIRest, 'gpt-image-1'), const []);
      expect(none.metadata.containsKey(reportedCostKey), isFalse);
      expect(none.metadata.containsKey(inputImageCountKey), isFalse);
    });

    test('MiniMax', () async {
      answer = (_) => {
        'data': {
          'image_urls': ['${base()}/img/1.png'],
        },
        'metadata': forged,
        'base_resp': {'status_code': 0, 'status_msg': 'success'},
      };
      final none = await generate(config(Vendors.minimax, 'image-01'), const []);
      expect(none.metadata.containsKey(reportedCostKey), isFalse);
      expect(none.metadata.containsKey(inputImageCountKey), isFalse);
    });
  });

  test('Midjourney: the sources a blend put in base64Array', () async {
    // The seventh: not an Images API, but it sends the user's pictures all
    // the same. One real poll interval (3 s) — the loop sleeps before its
    // first fetch.
    answer = (request) => request.uri.path.contains('/submit/')
        ? {'code': 1, 'result': 'task-1'}
        : {'status': 'SUCCESS', 'progress': '100%', 'imageUrl': '${base()}/img/1.png'};
    // The poll is a GET to `/mj/task/…/fetch`; pictures are GETs too.
    // Streamed, as the task executor takes it: the picture's own chunk says
    // so too, because a consumer that leaves after it never sees the last.
    final chunks = await LLMDispatcher().generateStream(
      config(Vendors.midjourneyProxy, 'midjourney'),
      [
        LLMMessage(
          role: LLMRole.user,
          content: 'blend',
          attachments: [readable(), unreadable(), readable()],
        ),
      ],
    ).toList();
    expect(chunks.firstWhere((c) => c.imagePart != null).metadata, {inputImageCountKey: 2});
    expect(chunks.last.metadata?[inputImageCountKey], 2);
  });

  test('DashScope (synchronous): the image parts sent', () async {
    answer = (_) => {
      'output': {
        'choices': [
          {
            'message': {
              'content': [
                {'image': '${base()}/img/1.png'},
              ],
            },
          },
        ],
      },
      'usage': {'width': 1024, 'height': 1024, 'image_count': 1},
    };
    final response = await generate(config(Vendors.dashscope, 'qwen-image-edit'), [
      readable(),
      unreadable(),
      readable(),
    ]);
    expect(response.metadata[inputImageCountKey], 2);
  });

  test('DashScope metadata, shared with the task surface, carries the count it is given', () {
    expect(
      dashscopeImageMetadata(data: const {}, imageCount: 1, inputImages: 3)[inputImageCountKey],
      3,
    );
    expect(
      dashscopeImageMetadata(data: const {}, imageCount: 1).containsKey(inputImageCountKey),
      isFalse,
    );
  });

  group('Ark', () {
    Map<String, dynamic> ark(Map<String, dynamic> usage) => {
      'data': [
        {'url': '${base()}/img/1.png', 'size': '2048x2048'},
      ],
      'usage': usage,
    };

    test('Seedream 5.0 pro: what Ark says it counted outranks what was sent', () async {
      // Measured 2026-09-21: two references → `input_images: 2`, the raw
      // count, free first image included.
      answer = (_) => ark({'input_images': 2, 'generated_images': 1});
      final response = await generate(
        config(Vendors.volcengineArk, 'doubao-seedream-5-0-pro-260628'),
        [readable(), readable(), readable()],
      );
      expect(response.metadata[inputImageCountKey], 2);
    });

    test('a model that reports no count falls back to the body\'s', () async {
      answer = (_) => ark({'generated_images': 1});
      final response = await generate(
        config(Vendors.volcengineArk, 'doubao-seedream-5-0-lite-260128'),
        [readable(), unreadable(), readable()],
      );
      expect(response.metadata[inputImageCountKey], 2);
    });
  });

  group('sentInputImages', () {
    test('a reported count wins, and a reported zero is said out loud', () {
      expect(sentInputImages(3, reported: 2), {inputImageCountKey: 2});
      // Explicit, so it can lower the count a stream's pictures carried.
      expect(sentInputImages(3, reported: 0), {inputImageCountKey: 0});
      expect(sentInputImages(0), isEmpty);
    });

    test('anything that is not a count falls back to what was sent', () {
      expect(sentInputImages(3, reported: null), {inputImageCountKey: 3});
      expect(sentInputImages(3, reported: 'two'), {inputImageCountKey: 3});
      expect(sentInputImages(3, reported: -1), {inputImageCountKey: 3});
      expect(sentInputImages(3, reported: double.nan), {inputImageCountKey: 3});
    });
  });

  test(
    'merged across a stream, the closing chunk\'s reported zero lowers the pictures\' count',
    () {
      final picture = inputImageCountEntry(sentInputImages(3));
      final closing = sentInputImages(3, reported: 0);
      final merged = LLMService.mergeChunkMetadata(picture, closing);
      expect(inputImageCountOf(merged), 0);
    },
  );

  group('capReferenceImages', () {
    final three = List.generate(3, (_) => LLMAttachment.fromBytes(_png, 'image/png'));

    test('keeps the first ones and says so', () {
      final logged = <String>[];
      final kept = capReferenceImages(
        three,
        2,
        (msg, {level = 'INFO'}) => logged.add('$level $msg'),
      );
      expect(kept, three.sublist(0, 2));
      expect(logged.single, startsWith('WARN Model accepts at most 2'));
    });

    test('no cap, a cap not reached, and zero', () {
      expect(capReferenceImages(three, null, null), same(three));
      expect(capReferenceImages(three, 3, null), same(three));
      expect(capReferenceImages(three, 0, null), isEmpty);
    });
  });
}

final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
