import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

void main() {
  group('RouteKind', () {
    test('ids round-trip and every kind speaks a chat wire', () {
      for (final k in RouteKind.values) {
        expect(RouteKind.tryParse(k.id), k);
        expect(k.face.surface, Surface.chat);
        expect(RouteKind.ofFace(k.face), k);
      }
      expect(RouteKind.tryParse('nope'), isNull);
      expect(RouteKind.tryParse(null), isNull);
      expect(RouteKind.ofFace(WireProtocol.openaiImages), isNull);
    });
  });

  group('platform table', () {
    final vendorIds = {for (final v in Vendors.all) v.id};

    test('every route names a real vendor that serves its face', () {
      for (final p in Platforms.all) {
        expect(p.routes, isNotEmpty, reason: p.id);
        final kinds = <RouteKind>{};
        for (final r in p.routes) {
          expect(
            kinds.add(r.kind),
            isTrue,
            reason: '${p.id} lists ${r.kind.id} twice',
          );
          expect(vendorIds, contains(r.vendorId), reason: '${p.id}/${r.kind}');
          expect(
            Vendors.byId(r.vendorId).menuFor(Surface.chat),
            contains(r.kind.face),
            reason: '${r.vendorId} does not serve ${r.kind.face}',
          );
        }
      }
    });

    test('unknown platform ids read as custom', () {
      expect(Platforms.byId('from-a-newer-build').id, Platforms.custom);
    });
  });

  group('inferPlatform', () {
    test('a vendor-specific id names its platform whatever the host', () {
      const cases = {
        Vendors.newApiOpenAI: Platforms.newapi,
        Vendors.newApiOpenAIResponses: Platforms.newapi,
        Vendors.newApiGemini: Platforms.newapi,
        Vendors.newApiAnthropic: Platforms.newapi,
        Vendors.dashscope: Platforms.dashscope,
        Vendors.dashscopeNative: Platforms.dashscope,
        Vendors.minimax: Platforms.minimax,
        Vendors.minimaxAnthropic: Platforms.minimax,
        Vendors.xaiApi: Platforms.xai,
        Vendors.deepseek: Platforms.deepseek,
        Vendors.volcengineArk: Platforms.ark,
        Vendors.midjourneyProxy: Platforms.midjourney,
        Vendors.ollama: Platforms.ollama,
        Vendors.lmStudio: Platforms.lmStudio,
        Vendors.minimaxH3Base: Platforms.h3Base,
        Vendors.officialGoogle: Platforms.google,
      };
      cases.forEach((vendor, platform) {
        expect(
          Platforms.inferPlatform(vendor, 'https://relay.example.com/v1').id,
          platform,
          reason: vendor,
        );
      });
    });

    test('a generic vendor is claimed by the host it points at', () {
      expect(
        Platforms.inferPlatform(
          Vendors.openAIRest,
          'https://api.openai.com/v1',
        ).id,
        Platforms.openai,
      );
      expect(
        Platforms.inferPlatform(
          Vendors.openAIResponsesRest,
          'https://API.OpenAI.com/v1',
        ).id,
        Platforms.openai,
      );
      expect(
        Platforms.inferPlatform(
          Vendors.anthropicRest,
          'https://api.anthropic.com/v1',
        ).id,
        Platforms.anthropic,
      );
      expect(
        Platforms.inferPlatform(
          Vendors.googleRest,
          'https://generativelanguage.googleapis.com/v1beta',
        ).id,
        Platforms.google,
      );
      // Google's OpenAI-compatible face is still Google.
      expect(
        Platforms.inferPlatform(
          Vendors.openAIRest,
          'https://generativelanguage.googleapis.com/v1beta/openai',
        ).id,
        Platforms.google,
      );
    });

    test('anything else is custom, including a non-URL endpoint', () {
      for (final vendor in [
        Vendors.openAIRest,
        Vendors.anthropicRest,
        Vendors.googleRest,
        'unknown-type',
      ]) {
        expect(
          Platforms.inferPlatform(vendor, 'https://relay.example.com/v1').id,
          Platforms.custom,
          reason: vendor,
        );
        expect(
          Platforms.inferPlatform(vendor, 'relay.example.com').id,
          Platforms.custom,
          reason: vendor,
        );
      }
    });
  });

  group('routeVendor', () {
    test('a face the primary vendor already offers stays with it', () {
      final ds = Platforms.byId(Platforms.dashscope);
      // A native-led Bailian channel reached the compatible and Anthropic
      // faces through its own vendor; migration must not change that.
      expect(
        Platforms.routeVendor(ds, Vendors.dashscopeNative, RouteKind.chat),
        Vendors.dashscopeNative,
      );
      expect(
        Platforms.routeVendor(ds, Vendors.dashscopeNative, RouteKind.anthropic),
        Vendors.dashscopeNative,
      );
      expect(
        Platforms.routeVendor(ds, Vendors.dashscope, RouteKind.dashscope),
        Vendors.dashscope,
      );
    });

    test(
      'a face the primary vendor never offered takes the platform vendor',
      () {
        final newapi = Platforms.byId(Platforms.newapi);
        expect(
          Platforms.routeVendor(newapi, Vendors.newApiOpenAI, RouteKind.gemini),
          Vendors.newApiGemini,
        );
        expect(
          Platforms.routeVendor(
            newapi,
            Vendors.newApiGemini,
            RouteKind.anthropic,
          ),
          Vendors.newApiAnthropic,
        );
        final mm = Platforms.byId(Platforms.minimax);
        expect(
          Platforms.routeVendor(mm, Vendors.minimax, RouteKind.anthropic),
          Vendors.minimaxAnthropic,
        );
      },
    );

    test('a face neither offers resolves to null', () {
      expect(
        Platforms.routeVendor(
          Platforms.byId(Platforms.deepseek),
          Vendors.deepseek,
          RouteKind.gemini,
        ),
        isNull,
      );
    });
  });

  test(
    'legacyKinds lists every chat face the vendor offered, default first',
    () {
      expect(Platforms.legacyKinds(Vendors.openAIRest), [
        RouteKind.chat,
        RouteKind.responses,
      ]);
      expect(Platforms.legacyKinds(Vendors.xaiApi), [
        RouteKind.responses,
        RouteKind.chat,
      ]);
      expect(Platforms.legacyKinds(Vendors.dashscopeNative), [
        RouteKind.dashscope,
        RouteKind.chat,
        RouteKind.anthropic,
      ]);
      expect(Platforms.legacyKinds(Vendors.deepseek), [RouteKind.chat]);
      expect(Platforms.legacyKinds(Vendors.newApiGemini), [RouteKind.gemini]);
      expect(Platforms.legacyKinds(Vendors.midjourneyProxy), [
        RouteKind.midjourney,
      ]);
      for (final v in Vendors.all) {
        expect(Platforms.legacyKinds(v.id), isNotEmpty, reason: v.id);
      }
    },
  );
}
