import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/xai_videos_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> bodies;
  setUp(() async {
    bodies = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/v1/videos/generations');
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>);
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"request_id":"job"}');
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    LLMClientPool.disposeAll();
  });

  LLMModelConfig config(String suffix, {String? profile}) => LLMModelConfig(
    modelId: 'grok-imagine-video$suffix',
    channelType: Vendors.xaiApi,
    endpoint: 'http://127.0.0.1:${server.port}/v1',
    apiKey: 'test',
    generationProfile: profile,
  );
  LLMAttachment image([LLMReferenceType role = LLMReferenceType.asset]) =>
      LLMAttachment.fromBytes(Uint8List.fromList([1, 2, 3]), 'image/png', referenceType: role);
  List<LLMMessage> history(List<LLMAttachment> media) => [
    LLMMessage(role: LLMRole.user, content: 'move', attachments: media),
  ];
  Future<LLMOperationTicket> submit(
    String suffix,
    List<LLMAttachment> media, [
    Map<String, dynamic> options = const {},
  ]) => LLMDispatcher().startLongRunning(config(suffix), history(media), options: options);

  test('native routing preserves all three model profiles', () {
    for (final (suffix, count, profile) in [
      ('', 7, 'grokImagineVideoClassic'),
      ('-1.5', 14, 'grokImagineVideo'),
      ('-1.5-lite', 0, 'grokImagineVideoLite'),
    ]) {
      final target = LLMDispatcher().resolveTarget(config(suffix));
      expect(target.model.capabilities.maxReferenceImages, count);
      expect(target.model.capabilities.profileId, profile);
    }
  });

  test('1.5 sends first, last and references together and counts every input', () async {
    final ticket = await submit(
      '-1.5',
      [image(LLMReferenceType.firstFrame), image(LLMReferenceType.lastFrame), image(), image()],
      {'resolution': '720p', 'seconds': '15'},
    );
    expect(ticket.inputImages, 4);
    final body = bodies.single;
    expect(body['image'], {'url': 'data:image/png;base64,AQID'});
    expect(body['last_frame'], body['image']);
    expect(body['reference_images'], [body['image'], body['image']]);
    expect(body['duration'], 15);
  });

  test('1.5 accepts a standalone last frame and first plus references', () async {
    expect((await submit('-1.5', [image(LLMReferenceType.lastFrame)])).inputImages, 1);
    expect(bodies.last.containsKey('image'), isFalse);
    expect(bodies.last.containsKey('last_frame'), isTrue);
    expect((await submit('-1.5', [image(LLMReferenceType.firstFrame), image()])).inputImages, 2);
    expect(bodies.last.keys, containsAll(['image', 'reference_images']));
  });

  test('1.5 permits fourteen references and rejects fifteen before POST', () async {
    await submit('-1.5', List.generate(14, (_) => image()));
    expect((bodies.single['reference_images'] as List).length, 14);
    await expectLater(
      submit('-1.5', List.generate(15, (_) => image())),
      throwsA(isA<LLMApiException>()),
    );
    expect(bodies, hasLength(1));
  });

  test('reference and pinned frame modes reject 1080p before POST', () async {
    for (final media in [
      [image()],
      [image(LLMReferenceType.lastFrame)],
      [image(LLMReferenceType.firstFrame), image()],
      [image(LLMReferenceType.firstFrame), image(LLMReferenceType.lastFrame)],
    ]) {
      await expectLater(
        submit('-1.5', media, {'resolution': '1080p'}),
        throwsA(isA<LLMApiException>()),
      );
    }
    expect(bodies, isEmpty);
  });

  test(
    'classic rejects unsupported resolution, long references, mixed frames and excess references',
    () async {
      for (final (media, options) in <(List<LLMAttachment>, Map<String, dynamic>)>[
        ([], {'resolution': '1080p'}),
        ([image()], {'seconds': '11'}),
        ([image(LLMReferenceType.lastFrame)], {}),
        ([image(LLMReferenceType.firstFrame), image()], {}),
        (List.generate(8, (_) => image()), {}),
      ]) {
        await expectLater(submit('', media, options), throwsA(isA<LLMApiException>()));
      }
      expect(bodies, isEmpty);
      await submit('', List.generate(7, (_) => image()), {'seconds': '10', 'resolution': '720p'});
      await submit('', [], {'seconds': '15'});
      expect(bodies, hasLength(2));
    },
  );

  test(
    'Lite rejects reference/last-frame inputs; Lite and 1.5 accept 1080p text and first frame',
    () async {
      for (final media in [
        [image()],
        [image(LLMReferenceType.lastFrame)],
      ]) {
        await expectLater(submit('-1.5-lite', media), throwsA(isA<LLMApiException>()));
      }
      expect(bodies, isEmpty);
      for (final suffix in ['-1.5', '-1.5-lite']) {
        for (final media in <List<LLMAttachment>>[
          [],
          [image(LLMReferenceType.firstFrame)],
        ]) {
          await submit(suffix, media, {'resolution': '1080p', 'seconds': '15'});
          expect(bodies.last['resolution'], '1080p');
        }
      }
    },
  );

  test('direct protocol callers also reject invalid and unreadable input before POST', () async {
    for (final (suffix, media) in [
      ('-1.5-lite', [image()]),
      ('-1.5', [LLMAttachment.fromBytes(null, 'image/png')]),
    ]) {
      await expectLater(
        XaiVideosProtocol().submit(LLMDispatcher().resolveTarget(config(suffix)), history(media)),
        throwsA(isA<LLMApiException>()),
      );
    }
    expect(bodies, isEmpty);
  });
}
