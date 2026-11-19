import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:joycai_image_ai_toolkits/services/llm/channel_upload_config.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_upload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_video_media.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/services/media/reference_media_probe.dart';

void main() {
  final dispatcher = LLMDispatcher();
  final config = LLMModelConfig(
    modelId: 'wan3.0-video',
    channelType: Vendors.dashscopeNative,
    endpoint: 'https://workspace.cn-beijing.maas.aliyuncs.com/api/v1',
    apiKey: 'test-secret',
  );
  LLMAttachment clip(String ext) => LLMAttachment.fromFile(
    File('test/support/reference_media/three_seconds.$ext'),
    'application/octet-stream',
    referenceType: ext == 'mp4' ? LLMReferenceType.referenceVideo : LLMReferenceType.referenceAudio,
  );
  final rejected = throwsA(isA<LLMApiException>());
  Map<String, String> policy() => {
    'upload_host': 'https://storage.example.test/',
    'upload_dir': 'dashscope-instant/test/attempt',
    'oss_access_key_id': 'signed-id',
    'signature': 'signed-signature',
    'policy': 'signed-policy',
    'x_oss_object_acl': 'private',
    'x_oss_forbid_overwrite': 'true',
  };
  Future<LLMOperationTicket> submit(List<LLMAttachment> inputs, {Map<String, dynamic>? options}) =>
      dispatcher.startLongRunning(config, [
        LLMMessage(role: LLMRole.user, content: '', attachments: inputs),
      ], options: options);
  setUp(LLMClientPool.disposeAll);
  tearDown(LLMClientPool.disposeAll);

  test('source video is uploaded first and counted as seconds, never images', () async {
    var uploads = 0;
    final urls = <String>[];
    await http.runWithClient(
      () async {
        final ticket = await dispatcher.startLongRunning(
          config,
          [
            LLMMessage(
              role: LLMRole.user,
              content: 'sunrise',
              attachments: [
                clip('mp4'),
                LLMAttachment.fromFile(
                  File('test/support/reference_media/three_seconds.mp4'),
                  'video/mp4',
                  referenceType: LLMReferenceType.sourceVideo,
                ),
              ],
            ),
          ],
          options: {'videoTask': 'extend'},
        );
        expect(ticket.inputImages, 0);
        expect(ticket.inputVideoSeconds, closeTo(6, .01));
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/uploads')) {
          return http.Response(jsonEncode({'data': policy()}), 200);
        }
        if (r.url.host == 'storage.example.test') {
          uploads++;
          urls.add(
            'oss://${RegExp(r'name="key"\r\n\r\n([^\r]+)').firstMatch(latin1.decode(r.bodyBytes))!.group(1)!}',
          );
          return http.Response('', 200);
        }
        final input = jsonDecode(r.body)['input'] as Map;
        expect(input['media'], [
          for (final url in urls) {'type': 'reference_video', 'url': url},
        ]);
        expect(input['prompt'], startsWith('Extend Video 1 backward'));
        expect(jsonDecode(r.body)['parameters']['duration'], -1);
        return http.Response('{"output":{"task_id":"edited"}}', 200);
      }),
    );
    expect(uploads, 2);
  });

  test('region routing preserves gateways and refuses unsupported official regions', () {
    expect(dashscopeUploadBase(config.endpoint), config.endpoint);
    expect(
      dashscopeUploadBase('https://ws.ap-southeast-1.maas.aliyuncs.com'),
      'https://ws.ap-southeast-1.maas.aliyuncs.com/api/v1',
    );
    expect(
      dashscopeUploadBase('https://dashscope-intl.aliyuncs.com/compatible-mode/v1'),
      'https://dashscope-intl.aliyuncs.com/api/v1',
    );
    expect(
      dashscopeUploadBase('https://gateway.test/custom/api/v1'),
      'https://gateway.test/custom/api/v1',
    );
    for (final host in ['ws.us-east-1.maas.aliyuncs.com', 'dashscope-us.aliyuncs.com']) {
      expect(() => dashscopeUploadBase('https://$host/api/v1'), rejected);
    }
  });

  test(
    'Token Plan source upload uses independent credentials and synthesis keeps plan key',
    () async {
      const host = 'token-plan.cn-beijing.maas.aliyuncs.com';
      for (final suffix in ['', '/api/v1', '/compatible-mode/v1', '/apps/anthropic']) {
        expect(dashscopeUploadBase('https://$host$suffix'), 'https://$host/api/v1');
      }
      final requests = <String>[];
      final bytes = await File('test/support/reference_media/three_seconds.mp4').readAsBytes();
      await http.runWithClient(
        () => dispatcher.startLongRunning(
          LLMModelConfig(
            modelId: 'wan3.0-video',
            channelType: Vendors.dashscopeNative,
            endpoint: 'https://$host',
            apiKey: 'test-plan-key',
            uploadConfig: const ChannelUploadConfig(
              tokenPlan: true,
              endpoint: 'https://dashscope.aliyuncs.com/api/v1',
              apiKey: 'upload-only-key',
            ),
          ),
          [
            LLMMessage(
              role: LLMRole.user,
              content: 'Add ocean sounds',
              attachments: [
                LLMAttachment.fromFile(
                  File('test/support/reference_media/three_seconds.mp4'),
                  'video/mp4',
                  referenceType: LLMReferenceType.sourceVideo,
                ),
              ],
            ),
          ],
          options: {'videoTask': 'edit'},
        ),
        () => MockClient((r) async {
          requests.add(r.url.path);
          if (r.url.path.startsWith('/api/v1/files')) {
            expect(r.url.host, 'dashscope.aliyuncs.com');
            expect(r.headers['Authorization'], 'Bearer upload-only-key');
            if (r.url.path.endsWith('/file-id')) {
              return http.Response(
                jsonEncode({
                  'data': {
                    'size': bytes.length,
                    'md5': md5.convert(bytes).toString(),
                    'url': 'https://storage.example.test/clip.mp4?signature=fresh',
                  },
                }),
                200,
              );
            }
            if (r.method == 'GET') {
              return http.Response('{"data":{"total":0,"files":[]}}', 200);
            }
            expect(latin1.decode(r.bodyBytes), contains('name="files"'));
            expect(latin1.decode(r.bodyBytes), contains('file-extract'));
            return http.Response(
              '{"data":{"uploaded_files":[{"file_id":"file-id"}],"failed_uploads":[]}}',
              200,
            );
          }
          expect(r.url.host, host);
          expect(r.headers['Authorization'], 'Bearer test-plan-key');
          expect(r.url.path, '/api/v1/services/aigc/video-generation/video-synthesis');
          expect(r.headers['X-DashScope-OssResourceResolve'], isNull);
          expect(
            jsonDecode(r.body)['input']['media'][0]['url'],
            'https://storage.example.test/clip.mp4?signature=fresh',
          );
          return http.Response('{"output":{"task_id":"edited"}}', 200);
        }),
      );
      expect(requests, [
        '/api/v1/files',
        '/api/v1/files',
        '/api/v1/files/file-id',
        '/api/v1/services/aigc/video-generation/video-synthesis',
      ]);
    },
  );

  test('schema and payload allow 10/5/5, reject sixth clips and frame combinations', () {
    final schema = LLMDispatcher.generationSchemaFor(
      channelType: Vendors.dashscopeNative,
      modelId: 'wan3.0-video',
      tag: 'video',
    );
    final media = [
      for (var i = 0; i < 10; i++) GenerationMedia(GenerationMediaRole.reference, '$i.png'),
      for (var i = 0; i < 5; i++) GenerationMedia(GenerationMediaRole.referenceVideo, '$i.mp4'),
      for (var i = 0; i < 5; i++) GenerationMedia(GenerationMediaRole.referenceAudio, '$i.wav'),
    ];
    final values = schema.readLegacy({});
    expect(schema.validate(values, media), isEmpty);
    final request = GenerationRequest(
      prompt: '',
      operation: schema.operation(values, media),
      values: values,
      media: media,
      modelId: config.modelId,
      channelType: config.channelType,
      protocolId: schema.protocol?.id,
      profileId: schema.profileId,
    );
    final restored = GenerationRequest.fromJson(jsonDecode(jsonEncode(request.toJson())));
    expect(restored.media.map((m) => m.path), media.map((m) => m.path));
    final wire = [
      for (final m in media)
        {
          'type': switch (m.role) {
            GenerationMediaRole.referenceVideo => 'reference_video',
            GenerationMediaRole.referenceAudio => 'reference_audio',
            _ => 'reference_image',
          },
          'url': m.path,
        },
    ];
    expect(
      (buildDashScopeVideoPayload(modelId: 'opaque', prompt: '', media: wire)['input']
          as Map)['media'],
      hasLength(20),
    );
    for (final role in [GenerationMediaRole.referenceVideo, GenerationMediaRole.referenceAudio]) {
      expect(schema.validate(values, [...media, GenerationMedia(role, 'extra')]), isNotEmpty);
      expect(
        () => buildDashScopeVideoPayload(
          modelId: 'opaque',
          prompt: '',
          media: [
            ...wire,
            {
              'type': role == GenerationMediaRole.referenceVideo
                  ? 'reference_video'
                  : 'reference_audio',
              'url': 'extra',
            },
          ],
        ),
        rejected,
      );
    }
    for (final role in ['reference_video', 'reference_audio']) {
      expect(
        () => buildDashScopeVideoPayload(
          modelId: 'opaque',
          prompt: '',
          media: [
            {'type': 'first_frame', 'url': 'frame'},
            {'type': role, 'url': 'clip'},
          ],
        ),
        rejected,
      );
    }
    expect(
      () => buildDashScopeVideoPayload(
        modelId: 'opaque',
        prompt: '',
        media: [
          {'type': 'file', 'url': 'file'},
        ],
      ),
      rejected,
    );
    final minimax = LLMDispatcher.generationSchemaFor(
      channelType: Vendors.minimax,
      modelId: 'MiniMax-H3',
      tag: 'video',
    );
    expect(minimax.contract.maxReferenceVideos, 3);
    expect(minimax.contract.maxReferenceAudios, 3);
    expect(minimax.contract.maxReferenceMedia, 12);
    expect(minimax.contract.minReferenceSeconds, 2);
  });

  test('metadata boundaries reject invalid dimensions, fps, formats and duration', () {
    for (final info in [
      const ReferenceMediaInfo('video/mp4', width: 240, height: 240, seconds: 1, fps: 16),
      const ReferenceMediaInfo('video/quicktime', width: 4096, height: 512, seconds: 15, fps: 60),
    ]) {
      validateWanVideoMediaInfo(info, video: true);
    }
    for (final info in [
      const ReferenceMediaInfo('video/mp4', width: 239, height: 240, seconds: 3, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 4097, height: 512, seconds: 3, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 1921, height: 240, seconds: 3, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 240, height: 1921, seconds: 3, fps: 24),
      const ReferenceMediaInfo('video/mp4', width: 240, height: 240, seconds: 3, fps: 15),
      const ReferenceMediaInfo('video/mp4', width: 240, height: 240, seconds: 3, fps: double.nan),
      const ReferenceMediaInfo('video/webm', width: 240, height: 240, seconds: 3, fps: 24),
    ]) {
      expect(() => validateWanVideoMediaInfo(info, video: true), rejected);
    }
    for (final seconds in [0.99, 15.01, double.nan, double.infinity]) {
      expect(
        () => validateWanVideoMediaInfo(
          ReferenceMediaInfo('audio/wav', seconds: seconds),
          video: false,
        ),
        rejected,
      );
    }
    expect(
      () => validateWanVideoMediaInfo(
        const ReferenceMediaInfo('audio/aac', seconds: 3),
        video: false,
      ),
      rejected,
    );
  });

  test(
    'all files validated and privately copied before upload; aggregate budgets and cleanup',
    () async {
      final prepared = await prepareDashScopeVideoMedia(
        [clip('mp4'), clip('wav'), clip('mp3')],
        outputSeconds: 27,
        checkCancelled: () {},
      );
      expect(prepared.videoSeconds, closeTo(3, 0.01));
      expect(prepared.files.map((f) => f.mime), ['video/mp4', 'audio/wav', 'audio/mpeg']);
      expect(
        await prepared.files.first.file.readAsBytes(),
        await File(clip('mp4').path!).readAsBytes(),
      );
      final dir = prepared.directory;
      await prepared.dispose();
      expect(await dir.exists(), false);
      for (final (inputs, seconds) in [
        ([clip('mp4')], 28),
        (List.generate(6, (_) => clip('mp4')), 5),
        (List.generate(6, (_) => clip('wav')), 5),
      ]) {
        await expectLater(
          prepareDashScopeVideoMedia(inputs, outputSeconds: seconds, checkCancelled: () {}),
          rejected,
        );
      }
      final smart = await prepareDashScopeVideoMedia(
        List.generate(5, (_) => clip('mp4')),
        outputSeconds: -1,
        checkCancelled: () {},
      );
      expect(smart.videoSeconds, closeTo(15, 0.01));
      await smart.dispose();
    },
  );

  test('size preflight and invalid later file stop before any network request', () async {
    final dir = await Directory.systemTemp.createTemp('wan-large-');
    addTearDown(() => dir.delete(recursive: true));
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        for (final (role, mb) in [
          (LLMReferenceType.referenceVideo, 100),
          (LLMReferenceType.referenceAudio, 15),
        ]) {
          final file = File('${dir.path}/large-$mb');
          final handle = await file.open(mode: FileMode.write);
          await handle.truncate(mb * 1024 * 1024 + 1);
          await handle.close();
          await expectLater(
            submit([LLMAttachment.fromFile(file, 'application/octet-stream', referenceType: role)]),
            rejected,
          );
        }
        await expectLater(
          submit([
            clip('wav'),
            LLMAttachment.fromBytes(
              Uint8List.fromList([1, 2, 3]),
              'video/mp4',
              referenceType: LLMReferenceType.referenceVideo,
            ),
          ]),
          rejected,
        );
      },
      () => MockClient((r) async {
        requests.add(r);
        return http.Response('{}', 500);
      }),
    );
    expect(requests, isEmpty);
  });

  test(
    'signed multipart isolates API key, fresh URLs per attempt, only synthesis marks body sent',
    () async {
      var bodySent = 0;
      var policies = 0;
      final keys = <String>[];
      final payloads = <Map<String, dynamic>>[];
      final photo = LLMAttachment.fromBytes(
        Uint8List.fromList(img.encodePng(img.Image(width: 240, height: 240, numChannels: 3))),
        'image/png',
      );
      final mock = MockClient((r) async {
        if (r.url.path.endsWith('/tasks/job')) {
          expect(r.method, 'GET');
          return http.Response('{"output":{"task_status":"RUNNING"}}', 200);
        }
        if (r.url.path.endsWith('/uploads')) {
          expect(bodySent, payloads.length);
          expect(r.method, 'GET');
          expect(r.url.host, Uri.parse(config.endpoint).host);
          expect(r.url.queryParameters, {'action': 'getPolicy', 'model': 'wan3.0-video'});
          expect(r.headers['Authorization'], 'Bearer test-secret');
          policies++;
          return http.Response(jsonEncode({'data': policy()}), 200);
        }
        if (r.url.host == 'storage.example.test') {
          expect(bodySent, payloads.length);
          expect(r.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
          final body = latin1.decode(r.bodyBytes);
          expect(body, contains('signed-policy'));
          expect(body, isNot(contains('test-secret')));
          expect(
            body.indexOf('name="success_action_status"'),
            lessThan(body.indexOf('name="file"')),
          );
          keys.add(RegExp(r'name="key"\r\n\r\n([^\r]+)').firstMatch(body)!.group(1)!);
          return http.Response('', 200);
        }
        expect(bodySent, payloads.length + 1);
        expect(r.headers['X-DashScope-OssResourceResolve'], 'enable');
        expect(r.headers['X-DashScope-Async'], 'enable');
        final payload = jsonDecode(r.body) as Map<String, dynamic>;
        payloads.add(payload);
        expect((payload['input'] as Map)['media'], [
          {'type': 'reference_image', 'url': 'oss://${keys[keys.length - 3]}'},
          {'type': 'reference_video', 'url': 'oss://${keys[keys.length - 2]}'},
          {'type': 'reference_audio', 'url': 'oss://${keys.last}'},
        ]);
        return http.Response('{"output":{"task_id":"job"}}', 200);
      });
      await http.runWithClient(() async {
        for (var i = 0; i < 2; i++) {
          final ticket = await submit(
            [photo, clip('mp4'), clip('wav')],
            options: {
              llmBodySentKey: () {
                bodySent++;
              },
            },
          );
          expect(ticket.name, 'job');
          expect(ticket.inputImages, 1);
          final polled = await dispatcher.checkOperation(
            config,
            ticket.name,
            surfaceId: ticket.surfaceId,
          );
          expect(polled['done'], false);
          expect(ticket.inputVideoSeconds, closeTo(3, 0.01));
        }
      }, () => mock);
      expect(policies, 6);
      expect(keys.toSet(), hasLength(6));
      expect(bodySent, 2);
    },
  );

  test('failed policy or upload never reaches synthesis or marks a paid submission', () async {
    for (final failure in ['policy', 'malformed', 'destination', 'upload']) {
      LLMClientPool.disposeAll();
      var requests = 0;
      var bodySent = false;
      await http.runWithClient(
        () async {
          await expectLater(
            submit(
              [clip('wav')],
              options: {
                llmBodySentKey: () {
                  bodySent = true;
                },
              },
            ),
            rejected,
          );
        },
        () => MockClient((r) async {
          requests++;
          if (requests == 1) {
            if (failure == 'policy') return http.Response('no', 403);
            if (failure == 'malformed') return http.Response('{}', 200);
            return http.Response(
              jsonEncode({
                'data': {
                  ...policy(),
                  if (failure == 'destination') 'upload_host': 'http://unsafe.test',
                },
              }),
              200,
            );
          }
          expect(failure, 'upload');
          return http.Response('failed', 500);
        }),
      );
      expect(requests, failure == 'upload' ? 2 : 1);
      expect(bodySent, false);
    }
  });

  test('cancel after policy or storage acknowledgement never starts paid submission', () async {
    for (final cancelAt in [1, 2]) {
      LLMClientPool.disposeAll();
      final abort = Completer<void>();
      var calls = 0;
      var sent = false;
      await http.runWithClient(
        () async {
          await expectLater(
            submit(
              [clip('wav')],
              options: {
                llmAbortTriggerKey: abort.future,
                llmBodySentKey: () {
                  sent = true;
                },
              },
            ),
            throwsA(isA<LLMCancelled>()),
          );
        },
        () => MockClient((r) async {
          calls++;
          if (calls == cancelAt) abort.complete();
          return http.Response(calls == 1 ? jsonEncode({'data': policy()}) : '', 200);
        }),
      );
      expect(calls, cancelAt);
      expect(sent, false);
    }
  });
}
