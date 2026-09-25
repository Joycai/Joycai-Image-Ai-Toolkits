import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/channel_merge.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// Standard 04 §5: the properties merge detection and planning must keep.
void main() {
  LLMChannel channel(
    int id,
    String type, {
    String endpoint = 'https://relay.example.com/v1',
    String key = 'sk-shared',
  }) => LLMChannel(id: id, displayName: 'c$id', endpoint: endpoint, apiKey: key, type: type);

  LLMModel model(
    int id,
    int channelId,
    String modelId, {
    String tag = 'chat',
    String? activeRoute,
    String? wireProtocol,
    int? cap,
    String? effort,
    String? routeParams,
  }) => LLMModel(
    id: id,
    modelId: modelId,
    modelName: modelId,
    tag: tag,
    channelId: channelId,
    activeRoute: activeRoute,
    wireProtocol: wireProtocol,
    maxOutputTokens: cap,
    reasoningEffort: effort,
    enableThinking: effort != null && effort != 'off',
    routeParams: routeParams,
  );

  // A New API relay split the pre-routes way: one channel per protocol.
  final openai = channel(1, Vendors.newApiOpenAI);
  final claude = channel(2, Vendors.newApiAnthropic);
  final gemini = channel(3, Vendors.newApiGemini, endpoint: 'https://relay.example.com/v1beta');

  group('detection', () {
    test('one key, one host, disjoint routes → a candidate, earlier kept', () {
      final found = ChannelMerge.candidates([openai, claude], const []);
      expect(found, hasLength(1));
      expect(found.single.keep.id, 1);
      expect(found.single.absorb.id, 2);
    });

    test('a different key never pairs', () {
      final other = channel(2, Vendors.newApiAnthropic, key: 'sk-other');
      expect(ChannelMerge.candidates([openai, other], const []), isEmpty);
    });

    test('a key that differs only in whitespace is another key', () {
      final padded = channel(2, Vendors.newApiAnthropic, key: 'sk-shared ');
      expect(ChannelMerge.candidates([openai, padded], const []), isEmpty);
    });

    test('overlapping routes never pair', () {
      final twin = channel(2, Vendors.newApiOpenAI);
      expect(ChannelMerge.candidates([openai, twin], const []), isEmpty);
    });

    test('another host or another platform never pairs', () {
      final elsewhere = channel(
        2,
        Vendors.newApiAnthropic,
        endpoint: 'https://other.example.com/v1',
      );
      final official = channel(2, Vendors.anthropicRest, endpoint: 'https://api.anthropic.com/v1');
      expect(ChannelMerge.candidates([openai, elsewhere], const []), isEmpty);
      expect(ChannelMerge.candidates([openai, official], const []), isEmpty);
    });

    test('the host is compared without case', () {
      final shouty = channel(2, Vendors.newApiAnthropic, endpoint: 'https://RELAY.example.com/v1');
      expect(ChannelMerge.candidates([openai, shouty], const []), hasLength(1));
    });

    test('an empty key pairs only with an empty key on a real host', () {
      final a = channel(1, Vendors.newApiOpenAI, key: '');
      final b = channel(2, Vendors.newApiAnthropic, key: '');
      expect(ChannelMerge.candidates([a, b], const []), hasLength(1));
      expect(ChannelMerge.candidates([a, claude], const []), isEmpty);
      final hostless = channel(1, Vendors.newApiOpenAI, endpoint: 'relay', key: '');
      final hostless2 = channel(2, Vendors.newApiAnthropic, endpoint: 'relay', key: '');
      expect(ChannelMerge.candidates([hostless, hostless2], const []), isEmpty);
    });

    test('each channel is in at most one candidate', () {
      final found = ChannelMerge.candidates([openai, claude, gemini], const []);
      expect(found, hasLength(1));
      expect({found.single.keep.id, found.single.absorb.id}, {1, 2});
    });
  });

  group('plan', () {
    test('the kept channel keeps its primary and gains the routes', () {
      final plan = ChannelMerge.plan(openai, claude, const [])!;
      final routes = RoutedChannel.routesOf(plan.channel);
      expect(routes.primary.kind, RoutedChannel.routesOf(openai).primary.kind);
      expect(plan.channel.type, openai.type);
      expect(plan.channel.endpoint, openai.endpoint);
      expect(plan.addedRoutes, [RouteKind.anthropic]);
      expect(routes.has(RouteKind.anthropic), isTrue);
      expect(plan.absorbedChannelId, 2);
    });

    test('a namesake merges: kept id, absorbed params parked on its route', () {
      final kept = model(10, 1, 'claude-sonnet-4-5', cap: 4096);
      final absorbed = model(20, 2, 'claude-sonnet-4-5', cap: 64000);
      final plan = ChannelMerge.plan(openai, claude, [kept, absorbed])!;
      expect(plan.deletes, [20]);
      expect(plan.idMap, {20: 10});
      expect(plan.mergedCount, 1);
      expect(plan.movedCount, 0);
      final written = plan.updates.single;
      expect(written.id, 10);
      expect(written.maxOutputTokens, 4096);
      expect(ModelRoutes.parked(written)[RouteKind.anthropic]?.maxOutputTokens, 64000);
    });

    test("the kept model's own parameters for a route win", () {
      final own = ModelRoutes.encodeParked({
        RouteKind.anthropic: const RouteParams(maxOutputTokens: 1000),
      });
      final kept = model(10, 1, 'x', routeParams: own);
      final absorbed = model(20, 2, 'x', cap: 64000);
      final plan = ChannelMerge.plan(openai, claude, [kept, absorbed])!;
      expect(plan.updates, isEmpty);
      expect(plan.idMap, {20: 10});
    });

    test('merging is one to one: a second namesake moves instead', () {
      final kept = model(10, 1, 'x');
      final first = model(20, 2, 'x');
      final second = model(21, 2, 'x');
      final plan = ChannelMerge.plan(openai, claude, [kept, first, second])!;
      expect(plan.idMap, {20: 10});
      expect(plan.movedCount, 1);
      expect(plan.updates.single.id, 21);
    });

    test('a moved model is sent exactly as before, its route pinned', () {
      final absorbed = model(20, 2, 'claude-opus-4-1', cap: 32000);
      final before = RoutedChannel.forModel(claude, absorbed);
      final plan = ChannelMerge.plan(openai, claude, [absorbed])!;
      final moved = plan.updates.single;
      expect(moved.id, 20);
      expect(moved.channelId, 1);
      expect(moved.activeRoute, 'anthropic');
      expect(moved.maxOutputTokens, 32000);
      final after = RoutedChannel.forModel(plan.channel, moved);
      expect(after.missing, isFalse);
      expect(after.route, before.route);
      expect(after.channelType, before.channelType);
      expect(after.endpoint, before.endpoint);
    });

    test('an absorbed route keeps its address byte for byte', () {
      final shouty = channel(2, Vendors.newApiAnthropic, endpoint: 'https://RELAY.example.com/v1');
      final plan = ChannelMerge.plan(openai, shouty, const [])!;
      expect(
        RoutedChannel.routesOf(plan.channel).addressOf(RouteKind.anthropic),
        'https://RELAY.example.com/v1',
      );
    });

    test('a kept model whose stale pin the merge would honour is pinned', () {
      // Pinned to the Anthropic face before the channel offered it, so it
      // followed the primary. After the merge the pin would suddenly apply.
      final stale = model(10, 1, 'x', wireProtocol: 'anthropic-chat');
      final before = RoutedChannel.forModel(openai, stale);
      final plan = ChannelMerge.plan(openai, claude, [stale])!;
      final pinned = plan.updates.single;
      expect(pinned.activeRoute, before.route.id);
      final after = RoutedChannel.forModel(plan.channel, pinned);
      expect(after.route, before.route);
      expect(after.endpoint, before.endpoint);
    });

    test('an image model with no namesake blocks that direction', () {
      final image = model(20, 3, 'gemini-2.5-flash-image', tag: 'image');
      expect(ChannelMerge.plan(claude, gemini, [image]), isNull);
      // …but it can stay where it is when the other channel is absorbed.
      final found = ChannelMerge.candidates([claude, gemini], [image]);
      expect(found.single.keep.id, 3);
      expect(found.single.plan.movedCount, 0);
    });

    test('a route another vendor would serve after the merge blocks it', () {
      // New API's OpenAI vendor serves Responses itself; under a Gemini
      // primary the Responses route would go to the platform's own vendor.
      expect(ChannelMerge.plan(gemini, openai, const []), isNull);
    });

    test('an image model with a namesake merges into it', () {
      final kept = model(10, 1, 'gpt-image-1', tag: 'image');
      final absorbed = model(20, 2, 'gpt-image-1', tag: 'image');
      final plan = ChannelMerge.plan(openai, claude, [kept, absorbed])!;
      expect(plan.idMap, {20: 10});
      expect(plan.updates, isEmpty);
    });
  });
}
