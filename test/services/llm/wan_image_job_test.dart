import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/image_job.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  test('persist accepted job then resume GET only without original references', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final methods = <String>[];
    var status = 'SUCCEEDED';
    server.listen((request) async {
      methods.add(request.method);
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'output': request.method == 'POST'
              ? {'task_id': 'job-1'}
              : {
                  'task_status': status,
                  'choices': [
                    {
                      'message': {
                        'content': [
                          {
                            'image': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
                          },
                        ],
                      },
                    },
                  ],
                },
        }),
      );
      await request.response.close();
    });
    final config = LLMModelConfig(
      modelId: 'wan2.7-image',
      channelType: Vendors.dashscopeNative,
      endpoint: 'http://127.0.0.1:${server.port}/api/v1',
      apiKey: 'test',
      wireProtocol: ImageJob.surface,
    );
    final dispatcher = LLMDispatcher();
    final messages = [LLMMessage(role: LLMRole.user, content: 'cat')];
    ImageJob? saved;
    await expectLater(
      dispatcher.generate(
        config,
        messages,
        options: {
          'imageSize': '1000x1000',
          ImageJob.callbackKey: (ImageJob job) async {
            saved = ImageJob.fromJson(jsonDecode(jsonEncode(job.toJson())));
            // Simulate stopping the process immediately after durable persistence.
            throw StateError('stopped');
          },
        },
      ),
      throwsA(isA<LLMJobAbandoned>()),
    );
    expect(methods, ['POST']);
    expect(saved!.sentSize, '1000*1000');
    final result = await dispatcher.generate(config, [], options: {ImageJob.resumeKey: saved});
    expect(result.generatedImages, hasLength(1));
    expect(result.metadata['dashscopeTaskId'], 'job-1');
    expect(methods, ['POST', 'GET']);
    status = 'UNKNOWN';
    await expectLater(
      dispatcher.generate(config, [], options: {ImageJob.resumeKey: saved}),
      throwsA(isA<LLMApiException>().having((e) => e.isJobEnded, 'ended', true)),
    );
    expect(methods, ['POST', 'GET', 'GET']);
  });
}
