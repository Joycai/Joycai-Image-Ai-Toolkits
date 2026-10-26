import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_image_batch_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

const ids = [
  'gpt-image-2',
  'gpt-image-2-2026-04-21',
  'gpt-image-2.5-flare',
  'gpt-image-2.5-flare-2026-09-08',
  'gpt-image-2.5-sunburst',
  'gpt-image-2.5-sunburst-2026-09-08',
];
void main() {
  for (final id in ids) {
    test('$id Batch capability is route and official-host gated', () {
      bool supports(String vendor, String endpoint, {String? wire}) =>
          LLMDispatcher.supportsImageBatch(
            channelType: vendor,
            modelId: id,
            endpoint: endpoint,
            wireProtocol: wire,
          );
      expect(supports(Vendors.openAIRest, 'https://api.openai.com/v1'), isTrue);
      expect(supports(Vendors.openAIResponsesRest, 'https://api.openai.com/v1'), isTrue);
      expect(supports(Vendors.newApiOpenAI, 'https://api.openai.com/v1'), isFalse);
      expect(supports(Vendors.openAIRest, 'https://relay.example/v1'), isFalse);
      expect(
        supports(Vendors.openAIRest, 'https://api.openai.com/v1', wire: 'chat-image'),
        isFalse,
      );
    });
    test('$id Batch generation and edit payload preserve options without streams', () async {
      final config = LLMModelConfig(
        modelId: id,
        channelType: Vendors.openAIRest,
        endpoint: 'https://api.openai.com/v1',
        apiKey: 'test',
      );
      for (final count in [0, 1, 2]) {
        final payload = await LLMDispatcher().imageBatchPayload(
          config,
          [
            LLMMessage(
              role: LLMRole.user,
              content: 'portrait',
              attachments: [
                for (var i = 0; i < count; i++) LLMAttachment.fromBytes(_png, 'image/png'),
              ],
            ),
          ],
          {
            'imageSize': '1536x1024',
            'quality': 'high',
            'background': 'transparent',
            'outputFormat': 'webp',
            'outputCompression': '70',
            'stream': true,
            'partial_images': 3,
          },
        );
        expect(payload['model'], id);
        expect(payload['n'], 1);
        expect(payload['size'], '1536x1024');
        expect(payload['output_format'], 'webp');
        expect(payload['background'], 'transparent');
        expect(payload['output_compression'], 70);
        expect(payload.containsKey('stream'), isFalse);
        expect(payload.containsKey('partial_images'), isFalse);
        if (count == 0) {
          expect(payload.containsKey('images'), isFalse);
        } else {
          expect(payload['images'], hasLength(count));
          expect(payload['images'][0]['image_url'], startsWith('data:image/png;base64,'));
        }
      }
    });
  }
  test('unsupported models and invalid options fail before sending', () async {
    expect(
      LLMDispatcher.supportsImageBatch(
        channelType: Vendors.openAIRest,
        modelId: 'gpt-image-1',
        endpoint: 'https://api.openai.com/v1',
      ),
      isFalse,
    );
    final config = LLMModelConfig(
      modelId: ids.first,
      channelType: Vendors.openAIRest,
      endpoint: 'https://api.openai.com/v1',
      apiKey: 'test',
    );
    await expectLater(
      LLMDispatcher().imageBatchPayload(
        config,
        [LLMMessage(role: LLMRole.user, content: 'p')],
        {'outputFormat': 'jpeg', 'background': 'transparent'},
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('wire uploads JSONL, creates once, correlates unordered outputs and cancels', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <(String, String, String)>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.add((request.method, request.uri.path, body));
      expect(request.headers.value('authorization'), 'Bearer test-key');
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      if (path == '/v1/files') {
        expect(body, contains('name="purpose"'));
        expect(body, contains('batch'));
        final line = body.split('\n').firstWhere((s) => s.startsWith('{"custom_id"'));
        final json = jsonDecode(line);
        expect(json['custom_id'], 'task-1');
        expect(json['url'], '/v1/images/edits');
        expect(json['body']['images'], hasLength(1));
        request.response.write(jsonEncode({'id': 'input-1'}));
      } else if (path == '/v1/batches' && request.method == 'POST') {
        final json = jsonDecode(body);
        expect(json['input_file_id'], 'input-1');
        expect(json['endpoint'], '/v1/images/edits');
        expect(json['completion_window'], '24h');
        expect(json['metadata']['joycai_intent'], 'intent-1');
        request.response.write(jsonEncode({'id': 'batch-1', 'status': 'validating'}));
      } else if (path == '/v1/files/output/content') {
        request.response.write('${jsonEncode({'custom_id': 'another', 'response': {}})}\n');
        request.response.write(
          '${jsonEncode({
            'custom_id': 'task-1',
            'response': {
              'status_code': 200,
              'body': {
                'data': [
                  {'b64_json': base64Encode(_png)},
                ],
              },
            },
          })}\n',
        );
      } else if (path.endsWith('/cancel')) {
        request.response.write(jsonEncode({'id': 'batch-1', 'status': 'cancelling'}));
      } else if (path == '/v1/batches') {
        request.response.write(
          jsonEncode({
            'data': [
              {
                'id': 'batch-1',
                'input_file_id': 'input-1',
                'metadata': {'joycai_intent': 'intent-1'},
              },
            ],
            'has_more': false,
          }),
        );
      } else {
        request.response.write(
          jsonEncode({'id': 'batch-1', 'status': 'completed', 'output_file_id': 'output'}),
        );
      }
      await request.response.close();
    });
    final target = LLMTarget(
      config: LLMModelConfig(
        modelId: ids.first,
        channelType: Vendors.openAIRest,
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'test-key',
      ),
      vendor: Vendors.byId(Vendors.openAIRest),
      model: ModelDescriptor.of(ids.first),
    );
    final protocol = OpenAIImageBatchProtocol();
    final payload = await protocol.payload(target, [
      LLMMessage(
        role: LLMRole.user,
        content: 'edit',
        attachments: [LLMAttachment.fromBytes(_png, 'image/png')],
      ),
    ], {});
    expect(await protocol.upload(target, 'task-1', payload), 'input-1');
    await protocol.create(target, 'input-1', 'intent-1', true);
    expect((await protocol.inspect(target, 'batch-1'))['status'], 'completed');
    final row = await protocol.resultLine(target, 'output', 'task-1');
    final result = await protocol.decodeResult(
      target,
      Map<String, dynamic>.from(row!['response']['body']),
      1,
    );
    expect(result.generatedImages.single, _png);
    expect((await protocol.reconcile(target, 'intent-1', 'input-1'))!['id'], 'batch-1');
    expect((await protocol.cancel(target, 'batch-1'))['status'], 'cancelling');
    expect(seen.where((r) => r.$1 == 'POST' && r.$2 == '/v1/batches'), hasLength(1));
  });
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
