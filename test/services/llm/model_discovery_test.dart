import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_descriptor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/midjourney_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  group('Model discovery', () {
    test('midjourney vendor lists the built-in catalog without any network', () async {
      final config = LLMModelConfig(
        modelId: 'discovery',
        channelType: Vendors.midjourneyProxy,
        endpoint: 'https://example.com',
        apiKey: 'k',
      );
      final target = LLMTarget(
        config: config,
        vendor: Vendors.byId(config.channelType),
        model: ModelDescriptor.of(config.modelId),
      );

      final models = await MidjourneyDiscoveryProtocol().fetchModels(target);

      expect(models, isNotEmpty);
      expect(models.map((m) => m.modelId), contains('midjourney'));
      expect(models.map((m) => m.modelId), contains('niji-journey'));
    });

    test('unknown channel types resolve to the generic OpenAI vendor', () {
      final vendor = Vendors.byId('some-unknown-type');
      expect(vendor.id, Vendors.openAIRest);
      expect(vendor.family, ProtocolFamily.openai);
    });

    test('network listings skip malformed and empty model entries', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        LLMClientPool.disposeAll();
        await server.close(force: true);
      });
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final payload = switch (request.uri.pathSegments.first) {
          'openai' => {
            'data': [
              null,
              7,
              {},
              {'id': ' '},
              {'id': 'gpt-x'},
            ],
          },
          'anthropic' => {
            'data': [
              'bad',
              {'id': ''},
              {'id': 'claude-x'},
            ],
          },
          _ => {
            'models': [
              false,
              {'name': 'models/'},
              {'name': 'models/gemini-x'},
            ],
          },
        };
        request.response.write(jsonEncode(payload));
        await request.response.close();
      });

      LLMTarget target(String family, String path) {
        final config = LLMModelConfig(
          modelId: 'discovery',
          channelType: family,
          endpoint: 'http://127.0.0.1:${server.port}/$path',
          apiKey: 'k',
        );
        return LLMTarget(
          config: config,
          vendor: Vendors.byId(family),
          model: ModelDescriptor.of(config.modelId),
        );
      }

      final openai = await OpenAIDiscoveryProtocol().fetchModels(
        target(Vendors.openAIRest, 'openai'),
      );
      final anthropic = await AnthropicDiscoveryProtocol().fetchModels(
        target(Vendors.anthropicRest, 'anthropic'),
      );
      final gemini = await GeminiDiscoveryProtocol().fetchModels(
        target(Vendors.googleRest, 'gemini'),
      );

      expect(openai.map((m) => m.modelId), ['gpt-x']);
      expect(anthropic.map((m) => m.modelId), ['claude-x']);
      expect(gemini.map((m) => m.modelId), ['gemini-x']);
    });
  });
}
