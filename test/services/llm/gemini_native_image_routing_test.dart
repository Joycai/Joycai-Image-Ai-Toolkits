import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  final dispatcher = LLMDispatcher();
  for (final id in ['gemini-3-pro-image', 'gemini-3.1-flash-image', 'gemini-nano-banana-2.1']) {
    test('$id exposes native images without changing auto or capabilities', () {
      for (final vendor in [Vendors.newApiOpenAI, Vendors.openAIRest, Vendors.officialGoogle]) {
        final menu = LLMDispatcher.protocolMenu(vendor, id);
        expect(menu.options, contains(WireProtocol.geminiImage));
        expect(menu.auto, WireProtocol.chatImage);
        final native = LLMDispatcher.generationSchemaFor(
          channelType: vendor,
          modelId: id,
          wireProtocol: WireProtocol.geminiImage.id,
        );
        final auto = LLMDispatcher.generationSchemaFor(channelType: vendor, modelId: id);
        expect(native.capabilities, same(auto.capabilities));
        expect(native.protocol, WireProtocol.geminiImage);
        expect(LLMDispatcher.isStaleProtocolSelection(vendor, id, 'gemini-image'), isFalse);
      }
    });
  }

  test('official native selection preserves its base and API-key authentication', () {
    final target = dispatcher.resolveTarget(
      LLMModelConfig(
        modelId: 'gemini-3-pro-image',
        channelType: Vendors.officialGoogle,
        endpoint: 'https://generativelanguage.googleapis.com/v1',
        apiKey: 'google-key',
        wireProtocol: 'gemini-image',
      ),
    );
    expect(target.config.endpoint, 'https://generativelanguage.googleapis.com/v1');
    expect(target.vendor.id, Vendors.officialGoogle);
    expect(target.headers().containsKey('Authorization'), isFalse);
    expect(
      target.decorateUrl(Uri.parse(target.config.endpoint)).queryParameters['key'],
      'google-key',
    );
    expect(
      LLMDispatcher.isStaleProtocolSelection(
        Vendors.newApiOpenAI,
        'gemini-3-pro-image',
        'gemini-image',
        tag: 'chat',
      ),
      isTrue,
    );
  });

  test('an opaque image alias can select its precise Gemini profile', () {
    final schema = LLMDispatcher.generationSchemaFor(
      channelType: Vendors.newApiOpenAI,
      modelId: 'nanoBananaPro',
      tag: 'image',
      wireProtocol: 'gemini-image',
      profile: 'geminiImagePro',
    );
    expect(schema.configurationDiagnostics, isEmpty);
    expect(schema.capabilities.isImageGenerator, isTrue);
    expect(schema.capabilities.maxReferenceImages, 14);
  });

  test('native base derivation preserves gateway prefixes and explicit native paths', () {
    expect(geminiImageBase('https://relay.test/v1/'), 'https://relay.test/v1beta');
    expect(geminiImageBase('https://relay.test/gateway/v1'), 'https://relay.test/gateway/v1beta');
    expect(geminiImageBase('https://relay.test'), 'https://relay.test/v1beta');
    expect(geminiImageBase('https://relay.test/custom'), 'https://relay.test/custom');
    expect(
      geminiImageBase('https://generativelanguage.googleapis.com/v1beta/openai'),
      'https://generativelanguage.googleapis.com/v1beta',
    );
  });

  for (final id in ['gemini-3-pro-image', 'gemini-3.1-flash-image', 'gemini-nano-banana-2.1']) {
    for (final customRoute in [false, true]) {
      test(
        '$id sync and stream use native payload, auth and route (custom=$customRoute)',
        () async {
          final requests = <http.Request>[];
          final reply = {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'inlineData': {
                        'mimeType': 'image/png',
                        'data': base64Encode([1, 2, 3]),
                      },
                    },
                  ],
                },
                'finishReason': 'STOP',
              },
            ],
          };
          final config = LLMModelConfig(
            modelId: id,
            channelType: Vendors.newApiOpenAI,
            endpoint: 'https://relay.test/v1',
            apiKey: 'test-key',
            wireProtocol: 'gemini-image',
            faceBases: customRoute ? {WireProtocol.geminiChat: 'https://native.test/custom'} : {},
          );
          final mock = MockClient((request) async {
            requests.add(request);
            return request.url.path.endsWith(':streamGenerateContent')
                ? http.Response(
                    'data: ${jsonEncode(reply)}\n\n',
                    200,
                    headers: {'content-type': 'text/event-stream'},
                  )
                : http.Response(
                    jsonEncode(reply),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
          });
          LLMClientPool.disposeAll();
          addTearDown(LLMClientPool.disposeAll);
          final history = [
            LLMMessage(
              role: LLMRole.user,
              content: 'Edit the image',
              attachments: [
                LLMAttachment.fromBytes(Uint8List.fromList([1, 2, 3]), 'image/png'),
              ],
            ),
          ];
          final options = {
            'imageSize': '2K',
            'aspectRatio': '16:9',
            if (id != 'gemini-3-pro-image') 'thinkingLevel': 'high',
          };
          expect(dispatcher.streamIsSingleShot(config), isFalse);
          await http.runWithClient(() async {
            final response = await dispatcher.generate(config, history, options: options);
            expect(response.generatedImages.single, [1, 2, 3]);
            final chunks = await dispatcher
                .generateStream(config, history, options: options)
                .toList();
            expect(chunks.where((c) => c.imagePart != null).single.imagePart, [1, 2, 3]);
          }, () => mock);
          final base = customRoute ? 'https://native.test/custom' : 'https://relay.test/v1beta';
          expect(
            requests.first.url.toString().split('?').first,
            '$base/models/$id:generateContent',
          );
          expect(requests.last.url.path, endsWith('/models/$id:streamGenerateContent'));
          expect(requests.last.url.queryParameters['alt'], 'sse');
          for (final request in requests) {
            expect(request.headers['Authorization'], 'Bearer test-key');
            expect(request.url.queryParameters.containsKey('key'), isFalse);
            final body = jsonDecode(request.body) as Map;
            expect(body['generationConfig']['responseModalities'], ['TEXT', 'IMAGE']);
            expect(body['generationConfig']['imageConfig'], {
              'imageSize': '2K',
              'aspectRatio': '16:9',
            });
            expect(
              body['contents'][0]['parts'],
              contains(containsPair('inlineData', {'mimeType': 'image/png', 'data': 'AQID'})),
            );
            if (id != 'gemini-3-pro-image') {
              expect(body['generationConfig']['thinkingConfig'], {'thinkingLevel': 'HIGH'});
            }
          }
        },
      );
    }
  }
}
