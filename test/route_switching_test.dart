import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/route_switching.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_model_config.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';

/// Standard 03 §6: the properties route switching must keep.
void main() {
  final routes = ChannelRoutes.create(
    Platforms.byId(Platforms.newapi),
    'https://relay.example.com',
    [RouteKind.chat, RouteKind.responses, RouteKind.anthropic],
  );

  LLMModel model({
    String? activeRoute,
    String? wireProtocol,
    int? cap = 65536,
    String? effort = 'high',
    bool thinking = true,
    bool webSearch = true,
    String? routeParams,
  }) => LLMModel(
    id: 42,
    modelId: 'claude-sonnet-4-5',
    modelName: 'Claude',
    tag: 'chat',
    channelId: 7,
    contextWindow: 200000,
    feeGroupId: 3,
    maxOutputTokens: cap,
    reasoningEffort: effort,
    enableThinking: thinking,
    enableWebSearch: webSearch,
    activeRoute: activeRoute,
    wireProtocol: wireProtocol,
    routeParams: routeParams,
  );

  test('switching to a route never configured leaves every param unset', () {
    final moved = RouteSwitching.switchRoute(
      model(),
      routes,
      RouteKind.anthropic,
    );
    expect(moved.activeRoute, 'anthropic');
    expect(moved.maxOutputTokens, isNull);
    expect(moved.reasoningEffort, isNull);
    expect(moved.enableThinking, isFalse);
    expect(RouteParams.ofModel(moved), RouteParams.empty);
  });

  test('switching away and back restores the values; the id never changes', () {
    final original = model();
    final there = RouteSwitching.switchRoute(
      original,
      routes,
      RouteKind.responses,
    );
    final configured = there.withRouteState(
      activeRoute: there.activeRoute,
      routeParams: there.routeParams,
      wireProtocol: there.wireProtocol,
      maxOutputTokens: 8000,
      enableThinking: true,
      reasoningEffort: 'low',
    );
    final back = RouteSwitching.switchRoute(configured, routes, RouteKind.chat);
    expect(back.id, original.id);
    expect(back.modelId, original.modelId);
    expect(back.activeRoute, 'chat');
    expect(back.maxOutputTokens, 65536);
    expect(back.reasoningEffort, 'high');
    expect(back.enableThinking, isTrue);
    // …and Responses kept what was set there.
    final again = RouteSwitching.switchRoute(back, routes, RouteKind.responses);
    expect(again.maxOutputTokens, 8000);
    expect(again.reasoningEffort, 'low');
  });

  test('model-scoped fields and the web search grant are untouched', () {
    final moved = RouteSwitching.switchRoute(
      model(),
      routes,
      RouteKind.anthropic,
    );
    expect(moved.enableWebSearch, isTrue);
    expect(moved.contextWindow, 200000);
    expect(moved.feeGroupId, 3);
    expect(moved.channelId, 7);
  });

  test('a rung the target route does not have is not carried', () {
    final ladder = RouteSwitching.ladderFor(
      model(),
      routes,
      RouteKind.anthropic,
    );
    // Park an Off on Anthropic, where adaptive thinking has no Off rung.
    final parked = ModelRoutes.encodeParked({
      RouteKind.anthropic: const RouteParams(reasoningEffort: 'off'),
    });
    final moved = RouteSwitching.switchRoute(
      model(routeParams: parked),
      routes,
      RouteKind.anthropic,
    );
    expect(ladder, isNot(contains(ReasoningEffort.off)));
    expect(moved.reasoningEffort, isNull);
    expect(moved.enableThinking, isFalse);
  });

  test('saving applies the same rule as switching', () {
    final stale = model(effort: 'telepathy', thinking: false, cap: -1);
    final saved = RouteSwitching.normalizedForSave(stale, routes);
    expect(saved.reasoningEffort, isNull);
    expect(saved.enableThinking, isFalse);
    expect(saved.maxOutputTokens, isNull);
    expect(saved.activeRoute, 'chat');
  });

  test('a legacy thinking flag alone saves as its Medium equivalent', () {
    final legacy = model(effort: null, thinking: true);
    final saved = RouteSwitching.normalizedForSave(legacy, routes);
    expect(saved.reasoningEffort, 'medium');
    expect(saved.enableThinking, isTrue);
  });

  test('the compat pin is written only where an older build can route it', () {
    final toAnthropic = RouteSwitching.switchRoute(
      model(),
      routes,
      RouteKind.anthropic,
    );
    // New API's OpenAI vendor never offered the Anthropic face.
    expect(toAnthropic.wireProtocol, isNull);
    final toResponses = RouteSwitching.switchRoute(
      model(),
      routes,
      RouteKind.responses,
    );
    expect(toResponses.wireProtocol, 'openai-responses');
  });

  test('preview lists what changes, unset shown as null', () {
    final changes = RouteSwitching.preview(
      model(),
      routes,
      RouteKind.responses,
    );
    expect(
      changes,
      contains(
        const RouteParamChange(RouteParamField.maxOutputTokens, 65536, null),
      ),
    );
    expect(
      changes,
      contains(
        const RouteParamChange(RouteParamField.reasoningEffort, 'high', null),
      ),
    );
  });

  group('changing the primary', () {
    test('pins the models that follow it, and only those', () {
      final follower = model();
      final chosen = model(activeRoute: 'responses');
      final legacyPin = model(wireProtocol: 'openai-responses');
      final stalePin = model(wireProtocol: 'gemini-chat');
      final gone = model(activeRoute: 'gemini');
      final image = LLMModel(
        modelId: 'gpt-image-1',
        modelName: 'img',
        tag: 'image',
      );
      final pinned = RouteSwitching.pinFollowers([
        follower,
        chosen,
        legacyPin,
        stalePin,
        gone,
        image,
      ], routes);
      expect(pinned, hasLength(2));
      expect(pinned.every((m) => m.activeRoute == 'chat'), isTrue);
      expect(pinned.first.maxOutputTokens, 65536);
    });

    test('a pinned follower stays on the old primary after the change', () {
      final follower = model();
      final pinned = RouteSwitching.pinFollowers([follower], routes).single;
      final moved = routes.withPrimary(RouteKind.responses);
      expect(ModelRoutes.displayRoute(follower, moved), RouteKind.responses);
      expect(ModelRoutes.displayRoute(pinned, moved), RouteKind.chat);
    });
  });

  test('modelsOnRoute counts the route each model rides', () {
    final ms = [
      model(),
      model(activeRoute: 'responses'),
      model(wireProtocol: 'openai-responses'),
      LLMModel(modelId: 'gpt-image-1', modelName: 'img', tag: 'image'),
    ];
    expect(RouteSwitching.modelsOnRoute(ms, routes, RouteKind.chat), 1);
    expect(RouteSwitching.modelsOnRoute(ms, routes, RouteKind.responses), 2);
    expect(RouteSwitching.modelsOnRoute(ms, routes, RouteKind.anthropic), 0);
  });
}
