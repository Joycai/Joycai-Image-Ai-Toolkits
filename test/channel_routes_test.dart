import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/channel_provider_presets.dart';

/// The address the dispatcher used for [face] on a channel stored as
/// ([type], [endpoint]) before routes existed: `_faceTarget`'s derivation.
String legacyAddress(String type, String endpoint, WireProtocol face) {
  final derive = Vendors.byId(type).protocolBases[face];
  return derive == null ? endpoint : derive(endpoint);
}

/// Every (type, endpoint) the add-channel catalogue can write, relays at a
/// typed host with their suffix.
List<(String, String)> presetChannels() {
  const relayHost = 'https://relay.example.com';
  final out = <(String, String)>[];
  for (final p in kChannelProviderPresets) {
    final variants = p.hasVariants
        ? [
            for (final v in p.variants)
              (v.channelType, v.defaultEndpoint, v.endpointSuffix),
          ]
        : [(p.channelType, p.defaultEndpoint, p.endpointSuffix)];
    for (final (type, endpoint, suffix) in variants) {
      out.add((type, endpoint ?? '$relayHost$suffix'));
    }
  }
  return out;
}

/// Stored endpoints that are not what a preset writes but exist in the wild.
const oddEndpoints = [
  'https://relay.example.com/v1/',
  'https://Relay.Example.com:8443/proxy/v1',
  'http://127.0.0.1:3000',
  'relay.example.com/v1',
  '  https://relay.example.com/v1  ',
  'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  'https://dashscope.aliyuncs.com/api/v1/',
  'https://dashscope.aliyuncs.com/apps/anthropic',
  'https://api.minimaxi.com/v2',
  'https://api.minimaxi.com',
  'https://generativelanguage.googleapis.com/v1beta/openai/',
  '',
];

void main() {
  group('read-time migration keeps every address byte for byte', () {
    void expectSameAddresses(String type, String endpoint) {
      final routes = ChannelRoutes.legacy(type, endpoint);
      final faces = Vendors.byId(type).menuFor(Surface.chat);
      expect(routes.kinds, [
        for (final f in faces) RouteKind.ofFace(f)!,
      ], reason: '$type @ "$endpoint"');
      for (final face in faces) {
        final kind = RouteKind.ofFace(face)!;
        expect(
          routes.addressOf(kind),
          legacyAddress(type, endpoint, face),
          reason: '$type @ "$endpoint" on ${face.id}',
        );
        expect(routes.faceBases[face], legacyAddress(type, endpoint, face));
      }
      // The flat endpoint is the primary route's address: the stored string
      // itself unless the vendor derives even its leading face.
      expect(routes.primaryAddress, legacyAddress(type, endpoint, faces.first));
      expect(routes.primaryVendorId, type);
      expect(routes.vendorOf(routes.primary.kind), type);
    }

    test('every preset and variant', () {
      final channels = presetChannels();
      expect(channels.length, greaterThan(20));
      for (final (type, endpoint) in channels) {
        expectSameAddresses(type, endpoint);
      }
    });

    test('every vendor at odd endpoints', () {
      for (final v in Vendors.all) {
        for (final e in oddEndpoints) {
          expectSameAddresses(v.id, e);
        }
      }
      expectSameAddresses('unknown-type', 'https://relay.example.com/v1');
    });

    test(
      'every migrated route resolves to the vendor it was pinned through',
      () {
        for (final (type, endpoint) in presetChannels()) {
          final routes = ChannelRoutes.legacy(type, endpoint);
          for (final k in routes.kinds) {
            expect(routes.vendorOf(k), type, reason: '$type ${k.id}');
          }
        }
      },
    );

    test('a default path is not stored, anything else is', () {
      final newapi = ChannelRoutes.legacy(
        Vendors.newApiOpenAI,
        'https://relay.example.com/v1',
      );
      expect(newapi.host, 'https://relay.example.com');
      expect(newapi.entries, const [
        RouteEntry(RouteKind.chat),
        RouteEntry(RouteKind.responses),
      ]);

      final slash = ChannelRoutes.legacy(
        Vendors.newApiOpenAI,
        'https://relay.example.com/v1/',
      );
      expect(slash.primary.path, '/v1/');

      final ds = ChannelRoutes.legacy(
        Vendors.dashscopeNative,
        'https://dashscope.aliyuncs.com/api/v1',
      );
      expect(ds.platform.id, Platforms.dashscope);
      expect(ds.entries, const [
        RouteEntry(RouteKind.dashscope),
        RouteEntry(RouteKind.chat),
        RouteEntry(RouteKind.anthropic),
      ]);

      final bare = ChannelRoutes.legacy(
        Vendors.openAIRest,
        'relay.example.com',
      );
      expect(bare.host, '');
      expect(bare.primary.path, 'relay.example.com');
    });
  });

  group('the stored document', () {
    test('round-trips through encode / resolve', () {
      for (final (type, endpoint) in presetChannels()) {
        final routes = ChannelRoutes.legacy(type, endpoint);
        final again = ChannelRoutes.resolve(
          routes.primaryVendorId,
          routes.primaryAddress,
          routes.encode(),
        );
        expect(again.entries, routes.entries, reason: type);
        expect(again.host, routes.host);
        expect(again.encode(), routes.encode());
      }
    });

    test('carries the write mark', () {
      final routes = ChannelRoutes.legacy(
        Vendors.newApiOpenAI,
        'https://r.example/v1',
      );
      final doc = jsonDecode(routes.encode()) as Map;
      expect(doc['mark'], {
        'type': Vendors.newApiOpenAI,
        'endpoint': 'https://r.example/v1',
      });
      expect(doc['v'], ChannelRoutes.docVersion);
    });

    test('a flat-only rewrite rebuilds the primary and keeps the rest', () {
      final routes = ChannelRoutes.create(
        Platforms.byId(Platforms.newapi),
        'https://relay.example.com',
        [RouteKind.chat, RouteKind.gemini, RouteKind.anthropic],
        paths: {RouteKind.gemini: 'https://gemini.example.com/v1beta'},
      );
      // An older build moved the channel to another host through the flat
      // columns alone.
      final rewritten = ChannelRoutes.resolve(
        Vendors.newApiOpenAI,
        'https://moved.example.com/v1',
        routes.encode(),
      );
      expect(rewritten.host, 'https://moved.example.com');
      expect(rewritten.primaryAddress, 'https://moved.example.com/v1');
      expect(rewritten.kinds, [
        RouteKind.chat,
        RouteKind.gemini,
        RouteKind.anthropic,
        RouteKind.responses,
      ]);
      expect(
        rewritten.addressOf(RouteKind.gemini),
        'https://gemini.example.com/v1beta',
      );
      expect(
        rewritten.addressOf(RouteKind.anthropic),
        'https://moved.example.com/v1',
      );
    });

    test('a flat-only change of type is detected too', () {
      final routes = ChannelRoutes.create(
        Platforms.byId(Platforms.newapi),
        'https://r.example',
        [RouteKind.chat, RouteKind.gemini],
      );
      final rewritten = ChannelRoutes.resolve(
        Vendors.newApiGemini,
        'https://r.example/v1beta',
        routes.encode(),
      );
      expect(rewritten.primary.kind, RouteKind.gemini);
      expect(rewritten.primaryVendorId, Vendors.newApiGemini);
      expect(rewritten.kinds, [RouteKind.gemini, RouteKind.chat]);
    });

    test('malformed or foreign documents read as absent, never as values', () {
      const type = Vendors.newApiOpenAI;
      const endpoint = 'https://r.example/v1';
      final legacy = ChannelRoutes.legacy(type, endpoint);
      for (final doc in [
        null,
        '',
        'not json',
        '[]',
        '{"host": 3, "routes": []}',
        '{"host": "https://r.example", "routes": "x"}',
        '{"host": "https://r.example", "routes": [{"kind": "telepathy"}]}',
      ]) {
        expect(
          ChannelRoutes.resolve(type, endpoint, doc).entries,
          legacy.entries,
          reason: '$doc',
        );
      }
      // Unknown kinds and duplicates inside a valid document are dropped.
      final mixed = jsonEncode({
        'host': 'https://r.example',
        'routes': [
          {'kind': 'chat'},
          {'kind': 'telepathy'},
          {'kind': 'chat', 'path': '/other'},
          {'kind': 'gemini', 'path': 7},
        ],
        'mark': {'type': type, 'endpoint': endpoint},
      });
      expect(ChannelRoutes.resolve(type, endpoint, mixed).entries, const [
        RouteEntry(RouteKind.chat),
        RouteEntry(RouteKind.gemini),
      ]);
    });

    test('a kind no vendor on the platform serves is dropped', () {
      final doc = jsonEncode({
        'host': 'https://api.deepseek.com',
        'routes': [
          {'kind': 'chat'},
          {'kind': 'gemini', 'path': '/v1beta'},
        ],
        'mark': {
          'type': Vendors.deepseek,
          'endpoint': 'https://api.deepseek.com',
        },
      });
      expect(
        ChannelRoutes.resolve(
          Vendors.deepseek,
          'https://api.deepseek.com',
          doc,
        ).kinds,
        [RouteKind.chat],
      );
    });
  });

  group('editing', () {
    final newapi = Platforms.byId(Platforms.newapi);

    test('create uses the platform vendors and defaults', () {
      final r = ChannelRoutes.create(newapi, 'https://relay.example.com', [
        RouteKind.chat,
        RouteKind.responses,
        RouteKind.anthropic,
        RouteKind.gemini,
      ]);
      expect(r.primaryVendorId, Vendors.newApiOpenAI);
      expect(r.vendorOf(RouteKind.responses), Vendors.newApiOpenAI);
      expect(r.vendorOf(RouteKind.gemini), Vendors.newApiGemini);
      expect(r.vendorOf(RouteKind.anthropic), Vendors.newApiAnthropic);
      expect(r.addressOf(RouteKind.gemini), 'https://relay.example.com/v1beta');
      expect(r.addressOf(RouteKind.anthropic), 'https://relay.example.com/v1');
    });

    test('a path equal to the default is stored as the default', () {
      final r = ChannelRoutes.create(newapi, 'https://r.example', [
        RouteKind.chat,
      ]).withPath(RouteKind.chat, '/v1');
      expect(r.primary.path, isNull);
      final changed = r.withPath(RouteKind.chat, '/api/v1');
      expect(changed.primary.path, '/api/v1');
      expect(changed.primaryAddress, 'https://r.example/api/v1');
      expect(changed.withPath(RouteKind.chat, null).primary.path, isNull);
    });

    test('an absolute path replaces host and path', () {
      final r = ChannelRoutes.create(
        newapi,
        'https://r.example',
        [RouteKind.chat, RouteKind.gemini],
        paths: {RouteKind.gemini: 'https://g.example/v1beta'},
      );
      expect(r.addressOf(RouteKind.gemini), 'https://g.example/v1beta');
      expect(
        r.withHost('https://s.example').addressOf(RouteKind.gemini),
        'https://g.example/v1beta',
      );
      expect(
        r.withHost('https://s.example').primaryAddress,
        'https://s.example/v1',
      );
    });

    test('the primary and the only route cannot be removed', () {
      final one = ChannelRoutes.create(newapi, 'https://r.example', [
        RouteKind.chat,
      ]);
      expect(one.withoutRoute(RouteKind.chat).kinds, [RouteKind.chat]);
      final two = one.withRoute(RouteKind.gemini);
      expect(two.kinds, [RouteKind.chat, RouteKind.gemini]);
      expect(two.withoutRoute(RouteKind.chat).kinds, two.kinds);
      expect(two.withoutRoute(RouteKind.gemini).kinds, [RouteKind.chat]);
    });

    test('a new primary takes the platform vendor for its route', () {
      final r = ChannelRoutes.create(newapi, 'https://r.example', [
        RouteKind.chat,
        RouteKind.gemini,
      ]).withPrimary(RouteKind.gemini);
      expect(r.kinds, [RouteKind.gemini, RouteKind.chat]);
      expect(r.primaryVendorId, Vendors.newApiGemini);
      expect(r.primaryAddress, 'https://r.example/v1beta');
      expect(r.vendorOf(RouteKind.chat), Vendors.newApiOpenAI);

      final ds = ChannelRoutes.legacy(
        Vendors.dashscope,
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      ).withPrimary(RouteKind.dashscope);
      expect(ds.primaryVendorId, Vendors.dashscopeNative);
      expect(ds.primaryAddress, 'https://dashscope.aliyuncs.com/api/v1');
      expect(
        ds.addressOf(RouteKind.chat),
        'https://dashscope.aliyuncs.com/compatible-mode/v1',
      );
    });
  });
}
