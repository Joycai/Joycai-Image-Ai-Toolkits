import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Pins the two ways a relay serves a Gemini image model — the OpenAI chat
/// shape and the Gemini-native shape — since the two disagree about which
/// side is responsible for which field.
void main() {
  final pixel = base64Encode([1, 2, 3]);

  LLMTarget target(String modelId) {
    final config = LLMModelConfig(
      modelId: modelId,
      channelType: Vendors.newApiOpenAI,
      endpoint: 'https://relay.example.com/v1',
      apiKey: 'k',
    );
    return LLMTarget(
      config: config,
      vendor: Vendors.byId(config.channelType),
      model: ModelDescriptor.of(config.modelId),
    );
  }

  group('extractStructuredImages', () {
    test('data URIs decode in place; http links are deferred to the caller', () {
      // The http form is what a relay backed by object storage returns. It
      // used to be dropped on the floor, which looked exactly like the model
      // generating nothing.
      final r = extractStructuredImages({
        'images': [
          {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$pixel'}},
          {'type': 'image_url', 'image_url': {'url': 'https://cdn.example.com/a.png'}},
        ]
      });
      expect(r.bytes, hasLength(1));
      expect(r.bytes.first, [1, 2, 3]);
      expect(r.urls, ['https://cdn.example.com/a.png']);
    });

    test('the flat image_url spelling and b64_json are both accepted', () {
      final flat = extractStructuredImages({
        'images': [
          {'image_url': 'https://cdn.example.com/b.png'},
          {'url': 'data:image/png;base64,$pixel'},
          {'b64_json': pixel},
        ]
      });
      expect(flat.urls, ['https://cdn.example.com/b.png']);
      expect(flat.bytes, hasLength(2));
    });

    test('the bare image_data field still works', () {
      final r = extractStructuredImages({'image_data': pixel});
      expect(r.bytes, hasLength(1));
      expect(r.urls, isEmpty);
    });

    test('absent or malformed fields yield nothing, never a throw', () {
      expect(extractStructuredImages({}).isEmpty, isTrue);
      expect(extractStructuredImages({'images': 'nope'}).isEmpty, isTrue);
      expect(extractStructuredImages({'images': ['nope']}).isEmpty, isTrue);
      expect(extractStructuredImages({'image_data': '!!not base64!!'}).isEmpty, isTrue);
      expect(extractStructuredImages({
        'images': [{'image_url': {'url': 'ftp://example.com/x.png'}}]
      }).isEmpty, isTrue);
    });
  });

  group('imageUrlsInText', () {
    test('a markdown image link is fetched whatever the host', () {
      // New API's own adapter writes `![image](data:…)`; relays that store
      // the file write the same shape with a link.
      expect(
        imageUrlsInText('here you go\n\n![image](https://cdn.example.com/a.png)'),
        ['https://cdn.example.com/a.png'],
      );
    });

    test('a bare link that is merely cited is left alone', () {
      // Downloading every URL a chat reply mentions is not acceptable; only
      // the historical Gemini bucket keeps its bare-link exemption.
      expect(imageUrlsInText('see https://cdn.example.com/a.png for details'), isEmpty);
      expect(
        imageUrlsInText('https://storage.googleapis.com/bucket/a.png'),
        ['https://storage.googleapis.com/bucket/a.png'],
      );
    });

    test('data URIs are not URLs to fetch — the base64 scan already has them', () {
      expect(imageUrlsInText('![image](data:image/png;base64,$pixel)'), isEmpty);
    });

    test('the same link twice is fetched once', () {
      expect(
        imageUrlsInText('![a](https://x.example/1.png) ![b](https://x.example/1.png)'),
        hasLength(1),
      );
    });
  });

  group('Gemini-via-OpenAI image config', () {
    final protocol = OpenAIChatProtocol();

    Map<String, dynamic> payloadWith(Map<String, dynamic>? options) =>
        protocol.buildChatPayloadForTest(
          target('gemini-2.5-flash-image'),
          [LLMMessage(role: LLMRole.user, content: 'a cat')],
          options: options,
          isStreaming: false,
        );

    test('the ratio and size also go out under extra_body.google.image_config', () {
      // New API reads *only* this path, and only these two snake_case keys —
      // the top-level copy alone was silently ignored, so the workbench's
      // aspect-ratio and 1K/2K/4K controls did nothing.
      final payload = payloadWith({'aspectRatio': '16:9', 'imageSize': '4K'});

      final google = (payload['extra_body'] as Map)['google'] as Map;
      expect(google['image_config'], {'aspect_ratio': '16:9', 'image_size': '4K'});
      // Keys New API rejects or ignores must not ride along in extra_body.
      expect((google['image_config'] as Map).containsKey('person_generation'), isFalse);
      expect((google['image_config'] as Map).containsKey('number_of_images'), isFalse);
      expect((google['image_config'] as Map).containsKey('aspectRatio'), isFalse);
    });

    test('the top-level dialect is kept for the hosts that read it', () {
      final payload = payloadWith({'aspectRatio': '16:9', 'imageSize': '4K'});
      expect(payload['image_config'], {
        'person_generation': 'allow_all',
        'aspect_ratio': '16:9',
        'image_size': '4K',
        'number_of_images': 1,
      });
    });

    test('nothing to configure means neither field is sent', () {
      final payload = payloadWith({'aspectRatio': 'not_set'});
      expect(payload.containsKey('image_config'), isFalse);
      expect(payload.containsKey('extra_body'), isFalse);
    });

    test('a non-Gemini model gets none of the extensions', () {
      final payload = protocol.buildChatPayloadForTest(
        target('gpt-5-chat'),
        [LLMMessage(role: LLMRole.user, content: 'hi')],
        options: {'aspectRatio': '16:9'},
        isStreaming: false,
      );
      expect(payload.containsKey('extra_body'), isFalse);
      expect(payload.containsKey('image_config'), isFalse);
      expect(payload.containsKey('modalities'), isFalse);
    });
  });

  group('Gemini native image request', () {
    final history = [LLMMessage(role: LLMRole.user, content: 'a cat')];

    test('an image model declares responseModalities — nobody else will', () {
      // A relay injects the modalities only when translating an OpenAI-shaped
      // request; on the native surface the field is ours to send.
      final payload = prepareGooglePayload(history, null, null, emitsImages: true);
      expect(payload['generationConfig']['responseModalities'], ['TEXT', 'IMAGE']);
    });

    test('a text model does not', () {
      final payload = prepareGooglePayload(history, null, null);
      expect(
        (payload['generationConfig'] as Map).containsKey('responseModalities'),
        isFalse,
      );
    });

    test('imageConfig keeps the native camelCase spelling', () {
      final payload = prepareGooglePayload(
        history,
        {'aspectRatio': '16:9', 'imageSize': '2K'},
        null,
        emitsImages: true,
      );
      expect(payload['generationConfig']['imageConfig'],
          {'aspectRatio': '16:9', 'imageSize': '2K'});
    });
  });

  group('Gemini blocking finish reasons', () {
    Map<String, dynamic> candidate(String finishReason, {List<dynamic>? parts}) => {
          'candidates': [
            {
              'finishReason': finishReason,
              if (parts != null) 'content': {'parts': parts},
            }
          ]
        };

    test('a block that produced nothing is a failure, not an empty success', () {
      // IMAGE_SAFETY and PROHIBITED_CONTENT are what the image models return;
      // both used to be logged at INFO and reported as a completed task with
      // no picture in it.
      for (final reason in ['IMAGE_SAFETY', 'PROHIBITED_CONTENT', 'SAFETY']) {
        expect(
          () => parseGoogleChunks(candidate(reason)).toList(),
          throwsA(predicate((e) => e.toString().contains(reason))),
          reason: reason,
        );
      }
    });

    test('a truncated answer is still an answer', () {
      final chunks = parseGoogleChunks(
        candidate('MAX_TOKENS', parts: [{'text': 'as far as I got'}]),
      ).toList();
      expect(chunks.single.textPart, 'as far as I got');
    });

    test('content that arrived before the block is kept', () {
      final chunks = parseGoogleChunks(
        candidate('SAFETY', parts: [{'text': 'partial'}]),
      ).toList();
      expect(chunks.single.textPart, 'partial');
    });

    test('a usage-only chunk stays legal — streams end with one', () {
      final chunks = parseGoogleChunks({
        'usageMetadata': {'promptTokenCount': 7}
      }).toList();
      expect(chunks.single.metadata, {'promptTokenCount': 7});
    });
  });
}
