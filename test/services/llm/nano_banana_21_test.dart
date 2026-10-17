import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  const id = 'gemini-nano-banana-2.1';
  final history = [LLMMessage(role: LLMRole.user, content: 'Draw a landscape')];
  final schema = LLMDispatcher.generationSchemaFor(
    channelType: Vendors.officialGoogle,
    modelId: id,
  );

  test('official and namespaced IDs discover as image models on the Gemini chat wire', () {
    for (final name in [id, 'models/$id', 'google/$id', id.toUpperCase()]) {
      expect(ModelFamilyClassifier.classify(name), ModelFamily.geminiImage);
      expect(ModelFamilyClassifier.inferTag(name), 'image');
      expect(ModelCapabilities.forModel(name).profileId, 'geminiImageV21');
    }
    expect(schema.protocol, WireProtocol.chatImage);
    expect(schema.capabilities.maxReferenceImages, 14);
    expect(ModelCapabilities.forModel('gemini-3.1-flash-image').profileId, 'geminiImageV2');
    expect(ModelFamilyClassifier.classify('gemini-2.5-flash'), ModelFamily.geminiChat);
  });

  test('schema rejects 512px, unsupported thinking, and a fifteenth reference', () {
    final valid = schema.readLegacy({
      'imageSize': '4K',
      'aspectRatio': '8:1',
      'thinkingLevel': 'high',
    });
    final media = List.generate(
      14,
      (i) => GenerationMedia(GenerationMediaRole.reference, '$i.png'),
    );
    expect(schema.validate(valid, media), isEmpty);
    expect(
      schema
          .validate(valid, [
            ...media,
            const GenerationMedia(GenerationMediaRole.reference, '15.png'),
          ])
          .map((d) => d.code),
      contains('tooManyReferences'),
    );
    for (final values in [
      {'imageSize': '512'},
      {'thinkingLevel': 'low'},
      {'aspectRatio': '7:1'},
    ]) {
      expect(
        schema.validate(schema.readLegacy(values), []).map((d) => d.code),
        contains('invalidParameter'),
      );
    }
    final aspect = schema.params.firstWhere((p) => p.key == 'aspectRatio');
    expect(aspect.legacy.options.where((o) => o.value != 'not_set'), hasLength(14));
  });

  test('native payload sends each thinking level and image settings; default omits them', () {
    for (final level in ['minimal', 'medium', 'high']) {
      final payload = prepareGooglePayload(
        history,
        schema.legacyOptions(
          schema.readLegacy({'thinkingLevel': level, 'aspectRatio': '1:8', 'imageSize': '2K'}),
        ),
        null,
        emitsImages: true,
      );
      expect(payload['generationConfig'], {
        'responseModalities': ['TEXT', 'IMAGE'],
        'thinkingConfig': {'thinkingLevel': level.toUpperCase()},
        'imageConfig': {'aspectRatio': '1:8', 'imageSize': '2K'},
      });
    }
    final defaults = prepareGooglePayload(
      history,
      schema.legacyOptions(schema.readLegacy({})),
      null,
      emitsImages: true,
    );
    expect(defaults['generationConfig'], {
      'responseModalities': ['TEXT', 'IMAGE'],
    });
  });

  test('compatible chat carries thinking even with default size and no conflicting effort', () {
    final config = LLMModelConfig(
      modelId: id,
      channelType: Vendors.newApiOpenAI,
      endpoint: 'https://relay.example/v1',
      apiKey: 'test',
      reasoningEffort: ReasoningEffort.high,
    );
    final target = LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(id),
    );
    final payload = prepareOpenAIChatPayload(target, history, {
      'thinkingLevel': 'minimal',
    }, isStreaming: false);
    expect(payload['modalities'], ['image', 'text']);
    expect(payload['extra_body'], {
      'google': {
        'thinking_config': {'thinking_level': 'minimal'},
      },
    });
    expect(payload.containsKey('reasoning_effort'), isFalse);
  });

  for (final transportId in [id, 'gemini-3.1-flash-image', 'gemini-3-pro-image']) {
    test(
      '$transportId uses native generation and streaming endpoints with identical options',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final seen = <(String, Map<String, dynamic>)>[];
        final responseBody = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'thought': true,
                    'inlineData': {
                      'data': base64Encode([9]),
                    },
                  },
                  {
                    'inlineData': {
                      'data': base64Encode([1, 2, 3]),
                    },
                  },
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        };
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
          seen.add((request.uri.path, body));
          if (request.uri.path.endsWith(':streamGenerateContent')) {
            request.response.headers.contentType = ContentType('text', 'event-stream');
            request.response.write('data: ${jsonEncode(responseBody)}\n\n');
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode(responseBody));
          }
          await request.response.close();
        });
        final config = LLMModelConfig(
          modelId: transportId,
          channelType: Vendors.officialGoogle,
          endpoint: 'http://127.0.0.1:${server.port}/v1beta',
          apiKey: 'test',
        );
        final options = {
          if (transportId != 'gemini-3-pro-image') 'thinkingLevel': 'high',
          'aspectRatio': '21:9',
          'imageSize': transportId == 'gemini-3.1-flash-image' ? '512' : '4K',
        };
        final dispatcher = LLMDispatcher();
        final result = await dispatcher.generate(config, history, options: options);
        expect(result.generatedImages.single, [1, 2, 3]);
        final chunks = await dispatcher.generateStream(config, history, options: options).toList();
        expect(chunks.where((c) => c.imagePart != null).single.imagePart, [1, 2, 3]);
        expect(seen.map((r) => r.$1), [
          '/v1beta/models/$transportId:generateContent',
          '/v1beta/models/$transportId:streamGenerateContent',
        ]);
        expect(seen.first.$2, seen.last.$2);
        expect(
          seen.first.$2['generationConfig']['thinkingConfig'],
          transportId == 'gemini-3-pro-image' ? isNull : {'thinkingLevel': 'HIGH'},
        );
        expect(seen.first.$2['generationConfig']['imageConfig']['imageSize'], options['imageSize']);
      },
    );
  }

  test('thought images never become output, while final images and usage survive', () {
    final chunks = parseGoogleChunks({
      'candidates': [
        {
          'content': {
            'parts': [
              {'thought': true, 'text': 'Planning'},
              {
                'thought': true,
                'inlineData': {'data': 'not even decoded'},
              },
              {
                'inlineData': {
                  'data': base64Encode([1, 2, 3]),
                },
              },
            ],
          },
          'finishReason': 'STOP',
        },
      ],
      'usageMetadata': {'candidatesTokenCount': 123},
    }).toList();
    expect(chunks.where((c) => c.imagePart != null).single.imagePart, [1, 2, 3]);
    expect(chunks.map((c) => c.reasoningPart).whereType<String>(), ['Planning']);
    expect(chunks.any((c) => c.metadata?['candidatesTokenCount'] == 123), isTrue);
  });
}
