import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_request.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_schema.dart';
import 'package:joycai_image_ai_toolkits/services/llm/generation/generation_validator.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_capabilities.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_family.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  for (final (id, topQuality) in [
    ('gpt-image-2', 'high'),
    ('gpt-image-2-2026-04-21', 'high'),
    ('gpt-image-2.5-flare', 'max'),
    ('gpt-image-2.5-flare-2026-09-08', 'max'),
    ('gpt-image-2.5-sunburst', 'max'),
    ('gpt-image-2.5-sunburst-2026-09-08', 'max'),
  ]) {
    test('$id validates quality, custom dimensions and reference limits', () {
      for (final name in [id, 'openai/$id', id.toUpperCase()]) {
        expect(ModelFamilyClassifier.classify(name), ModelFamily.openaiImage);
        final caps = ModelCapabilities.forModel(name);
        expect(caps.maxReferenceImages, 16);
        expect(caps.imageParams.firstWhere((p) => p.key == 'quality').options.map((o) => o.value), [
          'auto',
          'low',
          'medium',
          'high',
          if (topQuality == 'max') ...['xhigh', 'max'],
        ]);
      }
      final schema = LLMDispatcher.generationSchemaFor(
        channelType: Vendors.openAIRest,
        modelId: id,
      );
      final refs = List.generate(
        16,
        (i) => GenerationMedia(GenerationMediaRole.reference, '$i.png'),
      );
      expect(
        schema.validate(schema.readLegacy({'imageSize': '3840x2160', 'quality': topQuality}), refs),
        isEmpty,
      );
      expect(
        schema.validate(schema.readLegacy({}), [...refs, refs.first]).map((d) => d.code),
        contains('tooManyReferences'),
      );
      for (final size in ['512x512', '3840x3840', '1025x1024', '4096x1024', '3072x768']) {
        expect(
          schema.validate(schema.readLegacy({'imageSize': size}), []),
          isNotEmpty,
          reason: size,
        );
      }
      expect(
        schema
            .validate(schema.readLegacy({'background': 'transparent', 'outputFormat': 'jpeg'}), [])
            .map((d) => d.code),
        contains('transparentJpeg'),
      );
      for (final bad in ['-1', '101']) {
        expect(
          schema.validate(
            schema.readLegacy({'outputFormat': 'webp', 'outputCompression': bad}),
            [],
          ),
          isNotEmpty,
        );
      }
      final draft = schema.readLegacy({'outputFormat': 'png', 'outputCompression': '42'});
      expect(
        schema.effective(draft, GenerationOperation.textImage).containsKey('outputCompression'),
        isFalse,
      );
      expect(
        schema.effective({
          ...draft,
          ...schema.readLegacy({'outputFormat': 'webp', 'outputCompression': '0'}),
        }, GenerationOperation.textImage)['outputCompression']?.value,
        0,
      );
      if (topQuality == 'high') {
        expect(schema.validate(schema.readLegacy({'quality': 'max'}), []), isNotEmpty);
      }
    });

    test('$id routes generation and edits with exact model, size and quality', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <(String, String)>[];
      server.listen((request) async {
        seen.add((request.uri.path, await latin1.decoder.bind(request).join()));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'b64_json': base64Encode(_png)},
            ],
            'size': '1536x864',
            'quality': topQuality,
            'usage': {'input_tokens': 12, 'output_tokens': 34, 'total_tokens': 46},
          }),
        );
        await request.response.close();
      });
      final config = LLMModelConfig(
        modelId: id,
        channelType: Vendors.openAIRest,
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'test',
      );
      final dispatcher = LLMDispatcher();
      for (final count in [0, 1, 2]) {
        final format = ['png', 'jpeg', 'webp'][count];
        final background = count == 1 ? 'opaque' : 'transparent';
        final result = await dispatcher.generate(
          config,
          [
            LLMMessage(
              role: LLMRole.user,
              content: 'Draw a tree',
              attachments: [
                for (var i = 0; i < count; i++) LLMAttachment.fromBytes(_png, 'image/png'),
              ],
            ),
          ],
          options: {
            'imageSize': '1536x864',
            'quality': topQuality,
            'background': background,
            'outputFormat': format,
            'outputCompression': '0',
          },
        );
        expect(result.generatedImages.single, _png);
        expect(result.metadata['output_size'], '1536x864');
        expect(result.metadata['output_quality'], topQuality);
        expect(result.metadata['output_tokens'], 34);
        final (path, body) = seen.last;
        expect(path, count == 0 ? '/v1/images/generations' : '/v1/images/edits');
        if (count == 0) {
          expect(jsonDecode(body), {
            'model': id,
            'prompt': 'Draw a tree',
            'n': 1,
            'size': '1536x864',
            'quality': topQuality,
            'background': background,
            'output_format': format,
          });
        } else {
          for (final (key, value) in [
            ('model', id),
            ('size', '1536x864'),
            ('quality', topQuality),
            ('n', '1'),
            ('background', background),
            ('output_format', format),
            ('output_compression', '0'),
          ]) {
            expect(body, contains('name="$key"\r\n\r\n$value\r\n'));
          }
          expect(RegExp('filename="image_').allMatches(body), hasLength(count));
          expect(body, contains(count == 1 ? 'name="image";' : 'name="image[]";'));
          expect(body, isNot(contains('input_fidelity')));
          expect(body, isNot(contains('response_format')));
        }
      }
      final previousCount = seen.length;
      await expectLater(
        dispatcher.generate(
          config,
          [LLMMessage(role: LLMRole.user, content: 'Draw a tree')],
          options: {'background': 'transparent', 'outputFormat': 'jpeg'},
        ),
        throwsA(isA<LLMApiException>()),
      );
      expect(seen, hasLength(previousCount));
    });

    test('$id accepts old snapshots only with unchanged output defaults', () async {
      final schema = LLMDispatcher.generationSchemaFor(
        channelType: Vendors.openAIRest,
        modelId: id,
      );
      final values = schema.readLegacy({})
        ..remove('background')
        ..remove('outputFormat')
        ..remove('outputCompression');
      final request = GenerationRequest(
        prompt: 'tree',
        operation: GenerationOperation.textImage,
        values: values,
        media: [],
        modelId: id,
        channelType: Vendors.openAIRest,
        protocolId: schema.protocol?.id,
        profileId: schema.profileId,
      );
      final options = {...request.legacyOptions, GenerationRequest.taskKey: request.toJson()};
      final history = [LLMMessage(role: LLMRole.user, content: 'tree')];
      expect(await validateGeneration(schema, history, options), isNotNull);
      await expectLater(
        validateGeneration(schema, history, {...options, 'background': 'transparent'}),
        throwsA(isA<LLMApiException>()),
      );
    });
  }
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
