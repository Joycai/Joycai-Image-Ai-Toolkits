import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_validator.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  Map<String, dynamic> payload({
    Map<String, dynamic>? options,
    List<Map<String, String>> media = const [],
  }) => buildDashScopeVideoPayload(
    modelId: 'wan3.0-video',
    prompt: 'a cat',
    options: options,
    media: media,
  );
  final schema = LLMDispatcher.generationSchemaFor(
    channelType: Vendors.dashscopeNative,
    modelId: 'wan3.0-video',
    tag: 'video',
  );
  Uint8List png(int w, int h, {bool alpha = false}) =>
      Uint8List.fromList(img.encodePng(img.Image(width: w, height: h, numChannels: alpha ? 4 : 3)));
  final valid = png(240, 240);
  LLMAttachment attachment(Uint8List bytes, [LLMReferenceType? role]) =>
      LLMAttachment.fromBytes(bytes, 'image/png', referenceType: role ?? LLMReferenceType.media);
  Future<Map<String, dynamic>?> validate(
    List<LLMAttachment> attachments, [
    Map<String, dynamic>? options,
  ]) => validateGeneration(schema, [
    LLMMessage(role: LLMRole.user, content: 'a cat', attachments: attachments),
  ], options);
  final rejected = throwsA(isA<LLMApiException>());

  test('default and full video payload preserve every wire field', () {
    expect(payload(), {
      'model': 'wan3.0-video',
      'input': {'prompt': 'a cat'},
      'parameters': {'audio': true},
    });
    expect(
      payload(
        options: {
          'resolution': '720p',
          'aspectRatio': '21:9',
          'seconds': '12',
          'videoAudio': 'off',
          'promptExtend': 'on',
          'watermark': 'off',
        },
      )['parameters'],
      {
        'resolution': '720P',
        'ratio': '21:9',
        'duration': 12,
        'audio': false,
        'prompt_extend': true,
        'watermark': false,
      },
    );
    for (final (value, expected) in [
      ('480p', '480P'),
      ('720P', '720P'),
      ('1080p', '1080P'),
      ('4k', '1080P'),
    ]) {
      expect(
        (payload(options: {'resolution': value})['parameters'] as Map)['resolution'],
        expected,
      );
    }
    for (final (value, expected) in [('1', 2), ('30', 30), ('31', 30)]) {
      expect((payload(options: {'seconds': value})['parameters'] as Map)['duration'], expected);
    }
    for (final key in ['watermark', 'promptExtend']) {
      final wire = key == 'watermark' ? key : 'prompt_extend';
      for (final (value, expected) in [('on', true), ('off', false), ('not_set', null)]) {
        final parameters = payload(options: {key: value})['parameters'] as Map;
        expect(parameters[wire], expected);
        expect(parameters.containsKey(wire), expected != null);
      }
    }
  });

  test('media roles, frame exclusivity and ten reference boundary', () async {
    const frames = [
      {'type': 'first_frame', 'url': 'first'},
      {'type': 'last_frame', 'url': 'last'},
    ];
    expect((payload(media: frames)['input'] as Map)['media'], frames);
    const ref = {'type': 'reference_image', 'url': 'ref'};
    expect(() => payload(media: [...frames, ref]), rejected);
    expect(() => payload(media: [frames.first, ref]), rejected);
    expect(() => payload(media: [frames.last]), rejected);
    expect((payload(media: List.filled(10, ref))['input'] as Map)['media'], hasLength(10));
    expect(() => payload(media: List.filled(11, ref)), rejected);
    await validate(List.generate(10, (_) => attachment(valid)), {'aspectRatio': '21:9'});
    await expectLater(validate(List.generate(11, (_) => attachment(valid))), rejected);
    await validate([
      attachment(valid, LLMReferenceType.firstFrame),
      attachment(valid, LLMReferenceType.lastFrame),
    ]);
    await expectLater(
      validate([attachment(valid, LLMReferenceType.firstFrame), attachment(valid)]),
      rejected,
    );
    await expectLater(validate([attachment(valid, LLMReferenceType.lastFrame)]), rejected);
  });

  test('Wan video validates actual format, dimensions, ratio and alpha for every role', () async {
    for (final role in [null, LLMReferenceType.firstFrame]) {
      await validate([attachment(valid, role)]);
      for (final bytes in [
        png(240, 240, alpha: true),
        png(239, 240),
        png(240, 239),
        png(8001, 240),
        png(2161, 270),
        png(270, 2161),
        Uint8List.fromList(img.encodeGif(img.Image(width: 240, height: 240))),
        Uint8List.fromList([1, 2, 3]),
        Uint8List(20 * 1024 * 1024 + 1),
      ]) {
        await expectLater(validate([attachment(bytes, role)]), rejected);
      }
    }
    await validate([attachment(png(1920, 240))]);
    await validate([attachment(png(240, 1920))]);
    await expectLater(
      validate([
        attachment(valid, LLMReferenceType.firstFrame),
        attachment(png(240, 240, alpha: true), LLMReferenceType.lastFrame),
      ]),
      rejected,
    );
  });

  test('oversized path is rejected by 20 MB preflight', () async {
    final dir = await Directory.systemTemp.createTemp('wan-video-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/large.png');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(20 * 1024 * 1024 + 1);
    await handle.close();
    await expectLater(
      validate([LLMAttachment.fromFile(file, 'image/png')]),
      throwsA(
        isA<LLMApiException>().having(
          (e) => e.toString(),
          'size preflight',
          contains('exceeds 20 MB'),
        ),
      ),
    );
  });

  test('v1 snapshots may omit only default watermark, explicit tampering fails', () async {
    final oldValues = schema.effective(schema.readLegacy({}), GenerationOperation.textVideo)
      ..remove('watermark');
    final request = GenerationRequest(
      prompt: 'a cat',
      operation: GenerationOperation.textVideo,
      values: oldValues,
      media: const [],
      modelId: 'wan3.0-video',
      channelType: Vendors.dashscopeNative,
      protocolId: schema.protocol?.id,
      profileId: schema.profileId,
    );
    final options = generationTaskOptions({'generation': request.toJson()});
    expect(request.toJson()['version'], 1);
    await validate([], options);
    await validate([], {...options, 'watermark': 'not_set'});
    for (final value in ['on', 'off', 'invalid']) {
      await expectLater(validate([], {...options, 'watermark': value}), rejected);
    }
    await expectLater(validate([], {...options, 'videoAudio': 'off'}), rejected);
  });

  test('MaaS hosts infer DashScope and native bases without changing host', () {
    for (final host in [
      'workspace.cn-beijing.maas.aliyuncs.com',
      'ap-southeast-1.maas.aliyuncs.com',
    ]) {
      for (final suffix in ['', '/api/v1', '/compatible-mode/v1/']) {
        final endpoint = 'https://$host$suffix';
        expect(Platforms.inferPlatform(Vendors.openAIRest, endpoint).id, Platforms.dashscope);
        expect(dashscopeNativeBase(endpoint), 'https://$host/api/v1');
      }
    }
    expect(
      Platforms.inferPlatform(Vendors.openAIRest, 'https://maas.aliyuncs.com.evil.test').id,
      isNot(Platforms.dashscope),
    );
  });
}
