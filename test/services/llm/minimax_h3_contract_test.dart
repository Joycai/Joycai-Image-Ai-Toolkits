import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/minimax_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/minimax_video_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/media/reference_media_probe.dart';

void main() {
  final invalid = throwsA(isA<LLMApiException>());
  GenerationSchema schema(String id) =>
      LLMDispatcher.generationSchemaFor(channelType: Vendors.minimax, modelId: id, tag: 'video');
  Map<String, dynamic> payload(
    String id, {
    Map<String, dynamic>? options,
    List<MiniMaxVideoMedia> media = const [],
  }) => buildMiniMaxVideoPayload(modelId: id, prompt: 'animate', media: media, options: options);

  for (final (id, resolutions, minimum) in [
    ('MiniMax-H3', ['768P', '2K'], 4),
    ('MiniMax-H3-Highspeed', ['768P'], 4),
    ('MiniMax-H3-Lite', ['480P', '768P'], 4),
    ('MiniMax-H3-Max', ['480P', '768P'], 5),
  ]) {
    test('$id preserves its profile through dispatcher and validates every tier', () {
      final caps = schema(id).capabilities;
      expect(caps.maxReferenceImages, 9);
      expect(
        caps.videoParams.firstWhere((s) => s.key == 'resolution').options.map((o) => o.value),
        resolutions,
      );
      for (final res in ['480P', '768P', '2K']) {
        if (resolutions.contains(res)) {
          expect(
            payload(id, options: {'resolution': res, 'seconds': '$minimum'})['resolution'],
            res,
          );
        } else {
          expect(() => payload(id, options: {'resolution': res}), invalid);
        }
      }
      expect(payload(id, options: {'seconds': '$minimum'})['duration'], minimum);
      expect(payload(id, options: {'seconds': '15'})['duration'], 15);
      for (final seconds in ['${minimum - 1}', '16', '5.5']) {
        expect(() => payload(id, options: {'seconds': seconds}), invalid);
      }
    });
  }

  test('Lite requires a fixed reference ratio; frames always use adaptive', () {
    const refs = [MiniMaxVideoMedia(MiniMaxVideoRole.referenceImage, 'image')];
    expect(payload('MiniMax-H3-Lite', media: refs)['ratio'], '16:9');
    expect(
      () => payload('MiniMax-H3-Lite', media: refs, options: {'aspectRatio': 'adaptive'}),
      invalid,
    );
    const frame = [MiniMaxVideoMedia(MiniMaxVideoRole.lastFrame, 'image')];
    expect(
      payload('MiniMax-H3-Lite', media: frame, options: {'aspectRatio': '9:16'})['ratio'],
      'adaptive',
    );
    final s = schema('MiniMax-H3-Lite');
    const media = [GenerationMedia(GenerationMediaRole.lastFrame, 'last.png')];
    final values = s.effective(s.readLegacy({}), s.operation({}, media));
    expect(values['aspectRatio']?.value, 'adaptive');
    expect(s.validate(values, media), isEmpty);
  });

  test('Max expansion uses the documented nested spelling', () {
    expect(payload('MiniMax-H3-Max')['extra'], {'prompt_expansion_mode': 'balanced'});
    for (final mode in ['disabled', 'balanced', 'quality']) {
      expect(payload('MiniMax-H3-Max', options: {'promptExpansionMode': mode})['extra'], {
        'prompt_expansion_mode': mode,
      });
    }
    expect(() => payload('MiniMax-H3-Max', options: {'promptExpansionMode': 'balance'}), invalid);
    expect(payload('MiniMax-H3').containsKey('extra'), false);
  });

  test('nonempty Unicode prompt is required and counted by code points', () {
    for (final text in ['', '  ', 'a' * 7001]) {
      expect(
        () => buildMiniMaxVideoPayload(modelId: 'MiniMax-H3', prompt: text, media: []),
        invalid,
      );
    }
    expect(
      buildMiniMaxVideoPayload(modelId: 'MiniMax-H3', prompt: '😀' * 7000, media: [])['content'],
      isNotEmpty,
    );
  });

  test('all reference roles are nested and caps apply independently and jointly', () {
    final refs = [
      for (var i = 0; i < 9; i++) MiniMaxVideoMedia(MiniMaxVideoRole.referenceImage, 'image$i'),
      const MiniMaxVideoMedia(MiniMaxVideoRole.referenceVideo, 'video'),
      const MiniMaxVideoMedia(MiniMaxVideoRole.referenceAudio, 'audio'),
    ];
    final content = payload('MiniMax-H3', media: refs)['content'] as List;
    expect(content[10], {
      'type': 'video_url',
      'video_url': {'url': 'video'},
      'role': 'reference_video',
    });
    expect(content[11], {
      'type': 'audio_url',
      'audio_url': {'url': 'audio'},
      'role': 'reference_audio',
    });
    expect(() => payload('MiniMax-H3', media: [...refs, refs.first]), invalid);
    expect(
      () => payload(
        'MiniMax-H3',
        media: [...refs, const MiniMaxVideoMedia(MiniMaxVideoRole.firstFrame, 'frame')],
      ),
      invalid,
    );
    expect(() => payload('MiniMax-H3', media: List.filled(4, refs[9])), invalid);
    expect(() => payload('MiniMax-H3', media: List.filled(4, refs[10])), invalid);
    expect(() => payload('MiniMax-H3', media: [...refs, refs[9], refs[10]]), invalid);
    expect(() => validateMiniMaxBodySize(64 * 1024 * 1024), returnsNormally);
    expect(() => validateMiniMaxBodySize(64 * 1024 * 1024 + 1), invalid);
  });

  test('dimension, aspect, duration and frame-rate limits include their boundaries', () {
    expect(
      () => validateMiniMaxMediaInfo(
        const ReferenceMediaInfo('video/mp4', width: 640, height: 256, seconds: 2, fps: 23.976),
        video: true,
        audio: false,
      ),
      returnsNormally,
    );
    expect(
      () => validateMiniMaxMediaInfo(
        const ReferenceMediaInfo('audio/wav', seconds: 15),
        video: false,
        audio: true,
      ),
      returnsNormally,
    );
    for (final info in [
      const ReferenceMediaInfo('video/mp4', width: 255, height: 256, seconds: 3, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 5761, height: 4000, seconds: 3, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 641, height: 256, seconds: 3, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 256, height: 256, seconds: 1.9, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 256, height: 256, seconds: 15.1, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 256, height: 256, seconds: 3, fps: 23),
      const ReferenceMediaInfo('video/mp4', width: 256, height: 256, seconds: 3, fps: 61),
    ]) {
      expect(() => validateMiniMaxMediaInfo(info, video: true, audio: false), invalid);
    }
  });

  test('video/audio roles survive snapshot JSON and cannot leak into image paths', () {
    final s = schema('MiniMax-H3-Max');
    final original = GenerationRequest(
      prompt: 'p',
      operation: GenerationOperation.referenceVideo,
      values: s.readLegacy({}),
      media: const [
        GenerationMedia(GenerationMediaRole.referenceVideo, 'v.mp4'),
        GenerationMedia(GenerationMediaRole.referenceAudio, 'a.wav'),
      ],
      modelId: 'MiniMax-H3-Max',
      channelType: Vendors.minimax,
      protocolId: s.protocol?.id,
      profileId: s.profileId,
    );
    final restored = GenerationRequest.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.legacyOptions['referenceVideoPaths'], ['v.mp4']);
    expect(restored.legacyOptions['referenceAudioPaths'], ['a.wav']);
    expect(restored.legacyOptions['referenceImagePaths'], isEmpty);
    final other = LLMDispatcher.generationSchemaFor(
      channelType: Vendors.openAIRest,
      modelId: 'sora-2',
      tag: 'video',
    );
    expect(
      other.validate(other.readLegacy({}), restored.media).map((e) => e.code),
      contains('unsupportedReferenceMedia'),
    );
  });

  group('real transport', () {
    late HttpServer server;
    late List<Map<String, dynamic>> received;
    setUp(() async {
      received = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        received.add(jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"task_id":"h3_test"}');
        await request.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      LLMClientPool.disposeAll();
    });
    Future<LLMOperationTicket> submit(List<LLMAttachment> attachments) =>
        LLMDispatcher().startLongRunning(
          LLMModelConfig(
            modelId: 'MiniMax-H3-Max',
            channelType: Vendors.minimax,
            endpoint: 'http://127.0.0.1:${server.port}/v1',
            apiKey: 'test',
          ),
          [LLMMessage(role: LLMRole.user, content: 'animate', attachments: attachments)],
          options: {'resolution': '480P'},
        );
    LLMAttachment file(String name, LLMReferenceType role) => LLMAttachment.fromFile(
      File('test/support/reference_media/$name'),
      'application/octet-stream',
      referenceType: role,
    );

    test('mixed reference bytes reach correct wire roles and image usage stays accurate', () async {
      final ticket = await submit([
        LLMAttachment.fromBytes(
          Uint8List.fromList(img.encodePng(img.Image(width: 256, height: 256))),
          'image/png',
        ),
        file('three_seconds.mp4', LLMReferenceType.referenceVideo),
        file('three_seconds.wav', LLMReferenceType.referenceAudio),
      ]);
      expect(ticket.inputImages, 1);
      expect(received.single['resolution'], '480P');
      final content = received.single['content'] as List;
      expect(content[2]['video_url']['url'], startsWith('data:video/mp4;base64,'));
      expect(content[3]['audio_url']['url'], startsWith('data:audio/wav;base64,'));
    });
    test('per-file and aggregate duration limits stop the POST', () async {
      final wav = await File('test/support/reference_media/three_seconds.wav').readAsBytes();
      final longer = Uint8List.fromList(wav);
      // Real PCM samples with the byte rate changed to represent six seconds.
      final data = ByteData.sublistView(longer);
      for (var i = 12; i < longer.length - 24; i++) {
        if (String.fromCharCodes(longer.sublist(i, i + 4)) == 'fmt ') {
          data.setUint32(i + 16, data.getUint32(i + 16, Endian.little) ~/ 2, Endian.little);
          break;
        }
      }
      final ref = LLMAttachment.fromBytes(
        longer,
        'audio/wav',
        referenceType: LLMReferenceType.referenceAudio,
      );
      await expectLater(submit([ref, ref, ref]), invalid);
      final dir = await Directory.systemTemp.createTemp('h3_limits_');
      try {
        final file = File('${dir.path}/large.wav');
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(15 * 1024 * 1024 + 1);
        await handle.close();
        await expectLater(
          submit([
            LLMAttachment.fromFile(
              file,
              'audio/wav',
              referenceType: LLMReferenceType.referenceAudio,
            ),
          ]),
          invalid,
        );
      } finally {
        await dir.delete(recursive: true);
      }
      expect(received, isEmpty);
    });

    test('malformed, undersized, and short media never submit', () async {
      for (final attachment in [
        LLMAttachment.fromBytes(
          Uint8List.fromList([1, 2, 3]),
          'video/mp4',
          referenceType: LLMReferenceType.referenceVideo,
        ),
        LLMAttachment.fromBytes(
          Uint8List.fromList(img.encodePng(img.Image(width: 32, height: 32))),
          'image/png',
        ),
        LLMAttachment.fromBytes(
          Uint8List(0),
          'audio/wav',
          referenceType: LLMReferenceType.referenceAudio,
        ),
      ]) {
        await expectLater(submit([attachment]), invalid);
      }
      expect(received, isEmpty);
    });
  });
}
