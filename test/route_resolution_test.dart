import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/db/database_service.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_config_resolver.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// One request as the server saw it.
typedef Seen = ({String method, String url, String auth, String body});

/// A loopback server that records every request and answers 500, so a
/// dispatcher call sends exactly one request and then fails.
class Recorder {
  late HttpServer server;
  final List<Seen> seen = [];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      seen.add((
        method: req.method,
        url: req.uri.toString(),
        auth:
            '${req.headers.value('authorization')}|${req.headers.value('x-api-key')}|${req.headers.value('x-goog-api-key')}',
        body: body,
      ));
      req.response.statusCode = 500;
      req.response.write('{"error":{"message":"recorded"}}');
      await req.response.close();
    });
  }

  String get host => 'http://127.0.0.1:${server.port}';

  /// Sends one chat turn for [config] and returns what reached the server.
  Future<Seen> chat(LLMModelConfig config) async {
    seen.clear();
    try {
      await LLMDispatcher().generate(config, [
        LLMMessage(role: LLMRole.user, content: 'hi'),
      ]);
    } catch (_) {
      // The 500 is the point.
    }
    expect(
      seen,
      hasLength(1),
      reason: '${config.channelType} ${config.endpoint}',
    );
    return seen.single;
  }

  Future<Seen> discover(LLMModelConfig config) async {
    seen.clear();
    try {
      await LLMDispatcher().discoverModels(config);
    } catch (_) {}
    expect(seen, isNotEmpty);
    return seen.first;
  }
}

/// The config every request was built from before routes existed.
LLMModelConfig legacyConfig(
  String type,
  String endpoint,
  String modelId,
  String? pin,
) => LLMModelConfig(
  modelId: modelId,
  channelType: type,
  endpoint: endpoint,
  apiKey: 'k',
  tag: 'chat',
  wireProtocol: pin,
);

/// The config the resolver builds now, through the model's route.
LLMModelConfig routedConfig(LLMChannel channel, LLMModel model) {
  final routed = RoutedChannel.forModel(channel, model);
  expect(routed.missing, isFalse);
  return LLMModelConfig(
    modelId: model.modelId,
    channelType: routed.channelType,
    endpoint: routed.endpoint,
    apiKey: channel.apiKey,
    tag: model.tag,
    wireProtocol: routed.wireProtocol,
    faceBases: routed.faceBases,
  );
}

LLMModel chat(String modelId, {String? pin, String? route}) => LLMModel(
  id: 1,
  modelId: modelId,
  modelName: modelId,
  tag: 'chat',
  wireProtocol: pin,
  activeRoute: route,
);

void main() {
  final rec = Recorder();
  setUpAll(() async {
    // flutter_test answers every real request with a 400 of its own.
    HttpOverrides.global = null;
    await rec.start();
  });
  tearDownAll(() => rec.server.close(force: true));

  group(
    'every legacy (channel, pin) sends the same request through routes',
    () {
      test('each preset at its own path, each chat face', () async {
        var checked = 0;
        for (final p in kChannelProviderPresets) {
          final variants = p.hasVariants
              ? [
                  for (final v in p.variants)
                    (v.channelType, v.defaultEndpoint, v.endpointSuffix),
                ]
              : [(p.channelType, p.defaultEndpoint, p.endpointSuffix)];
          for (final (type, preset, suffix) in variants) {
            if (type == Vendors.midjourneyProxy) continue;
            final path = preset == null
                ? suffix
                : ChannelRoutes.splitHost(preset).$2;
            final endpoint = '${rec.host}$path';
            final channel = LLMChannel(
              displayName: p.id,
              endpoint: endpoint,
              apiKey: 'k',
              type: type,
            );
            final modelId = type.startsWith('dashscope')
                ? 'qwen-plus'
                : 'test-model';
            for (final face in Vendors.byId(type).menuFor(Surface.chat)) {
              for (final pin in {null, face.id}) {
                if (pin == null &&
                    face != Vendors.byId(type).menuFor(Surface.chat).first) {
                  continue;
                }
                final before = await rec.chat(
                  legacyConfig(type, endpoint, modelId, pin),
                );
                final after = await rec.chat(
                  routedConfig(channel, chat(modelId, pin: pin)),
                );
                expect(after, before, reason: '$type pin=$pin');
                checked++;
              }
            }
          }
        }
        expect(checked, greaterThan(25));
      });

      test('discovery on every preset lists from the same address', () async {
        for (final p in kChannelProviderPresets) {
          final type = p.channelType;
          if (type == Vendors.midjourneyProxy) continue;
          final path = p.defaultEndpoint == null
              ? p.endpointSuffix
              : ChannelRoutes.splitHost(p.defaultEndpoint!).$2;
          final endpoint = '${rec.host}$path';
          final channel = LLMChannel(
            displayName: p.id,
            endpoint: endpoint,
            apiKey: 'k',
            type: type,
          );
          final routed = RoutedChannel.primary(channel);
          final before = await rec.discover(
            LLMModelConfig(
              modelId: 'discovery',
              channelType: type,
              endpoint: endpoint,
              apiKey: 'k',
            ),
          );
          final after = await rec.discover(
            LLMModelConfig(
              modelId: 'discovery',
              channelType: routed.channelType,
              endpoint: routed.endpoint,
              apiKey: 'k',
              faceBases: routed.faceBases,
            ),
          );
          expect(after, before, reason: type);
        }
      });
    },
  );

  group('a merged relay channel', () {
    late LLMChannel channel;
    setUp(() {
      final routes =
          ChannelRoutes.create(Platforms.byId(Platforms.newapi), rec.host, [
            RouteKind.chat,
            RouteKind.responses,
            RouteKind.anthropic,
            RouteKind.gemini,
          ]);
      channel = LLMChannel(
        displayName: 'relay',
        endpoint: routes.primaryAddress,
        apiKey: 'k',
        type: routes.primaryVendorId,
        routes: routes.encode(),
      );
    });

    test('each route sends what its own legacy channel sent', () async {
      const legacy = {
        RouteKind.chat: (Vendors.newApiOpenAI, '/v1'),
        RouteKind.responses: (Vendors.newApiOpenAIResponses, '/v1'),
        RouteKind.anthropic: (Vendors.newApiAnthropic, '/v1'),
        RouteKind.gemini: (Vendors.newApiGemini, '/v1beta'),
      };
      for (final MapEntry(key: kind, value: (type, path)) in legacy.entries) {
        final modelId = kind == RouteKind.gemini
            ? 'gemini-2.5-flash'
            : 'claude-sonnet-5';
        final before = await rec.chat(
          legacyConfig(type, '${rec.host}$path', modelId, null),
        );
        final after = await rec.chat(
          routedConfig(channel, chat(modelId, route: kind.id)),
        );
        expect(after, before, reason: kind.id);
      }
    });

    test('a path the user set is honored for chat and for discovery', () async {
      final routes = RoutedChannel.routesOf(channel)
          .withPath(RouteKind.gemini, '${rec.host}/g/v1beta')
          .withPath(RouteKind.chat, '/api/v1');
      final moved = LLMChannel(
        displayName: 'relay',
        endpoint: routes.primaryAddress,
        apiKey: 'k',
        type: routes.primaryVendorId,
        routes: routes.encode(),
      );
      final g = await rec.chat(
        routedConfig(moved, chat('gemini-2.5-flash', route: 'gemini')),
      );
      expect(
        Uri.parse(g.url).path,
        startsWith('/g/v1beta/models/gemini-2.5-flash'),
      );
      final c = await rec.chat(routedConfig(moved, chat('gpt-5.2')));
      expect(Uri.parse(c.url).path, '/api/v1/chat/completions');
    });
  });

  group('LLMConfigResolver', () {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    usePrivateDataDir('joycai_route_resolution_test');

    test(
      'resolves the model route, and refuses a route that is gone',
      () async {
        final db = DatabaseService();
        final routes = ChannelRoutes.create(
          Platforms.byId(Platforms.newapi),
          'https://relay.example.com',
          [RouteKind.chat, RouteKind.gemini],
        );
        final channelId = await db.addChannel({
          'display_name': 'relay',
          'type': routes.primaryVendorId,
          'endpoint': routes.primaryAddress,
          'api_key': 'k',
          'routes': routes.encode(),
        });
        final onGemini = await db.addModel({
          'model_id': 'gemini-2.5-flash',
          'model_name': 'g',
          'tag': 'chat',
          'channel_id': channelId,
          'active_route': 'gemini',
        });
        final onAnthropic = await db.addModel({
          'model_id': 'claude-sonnet-5',
          'model_name': 'c',
          'tag': 'chat',
          'channel_id': channelId,
          'active_route': 'anthropic',
        });

        final config = await LLMConfigResolver().resolveConfig(onGemini);
        expect(config.channelType, Vendors.newApiGemini);
        expect(config.endpoint, 'https://relay.example.com/v1beta');
        expect(
          config.faceBases[WireProtocol.openaiChat],
          'https://relay.example.com/v1',
        );

        await expectLater(
          LLMConfigResolver().resolveConfig(onAnthropic),
          throwsA(
            isA<LLMConfigException>().having(
              (e) => e.kind,
              'kind',
              LLMConfigErrorKind.routeNotFound,
            ),
          ),
        );
      },
    );
  });
}
