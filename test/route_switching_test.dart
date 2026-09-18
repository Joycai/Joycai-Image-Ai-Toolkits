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

  group('an effort off the ladder keeps the request it sends', () {
    const boolean = [null, ReasoningEffort.off, ReasoningEffort.medium];
    const gemini = [
      null,
      ReasoningEffort.off,
      ReasoningEffort.low,
      ReasoningEffort.medium,
      ReasoningEffort.high,
    ];
    const adaptive = [
      null,
      ReasoningEffort.low,
      ReasoningEffort.medium,
      ReasoningEffort.high,
      ReasoningEffort.max,
    ];
    RouteParams at(String effort, List<ReasoningEffort?> ladder) =>
        RouteSwitching.forRoute(
          RouteParams(reasoningEffort: effort, enableThinking: true),
          ladder,
        );

    test('a boolean switch keeps any "on" as on', () {
      for (final e in ['low', 'high', 'max']) {
        expect(at(e, boolean).reasoningEffort, 'medium', reason: e);
        expect(at(e, boolean).enableThinking, isTrue, reason: e);
      }
    });

    test('Max on Gemini is its top rung', () {
      expect(at('max', gemini).reasoningEffort, 'high');
    });

    test('Off where there is no Off rung, or no rung at all, is unset', () {
      expect(at('off', adaptive), RouteParams.empty);
      expect(at('high', const []), RouteParams.empty);
    });

    test('a rung below every on rung takes the lowest', () {
      expect(
        at('low', const [null, ReasoningEffort.medium]).reasoningEffort,
        'medium',
      );
    });
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

  group('a route gone from the channel', () {
    // Chose Gemini, which this channel no longer offers; Chat has its own
    // values parked.
    LLMModel stranded() => model(
      activeRoute: 'gemini',
      cap: 32768,
      effort: 'low',
      routeParams: ModelRoutes.encodeParked({
        RouteKind.chat: const RouteParams(maxOutputTokens: 4096),
      }),
    );

    test("opens on the primary with the primary's own values", () {
      final recovered = RouteSwitching.recoverMissingRoute(stranded(), routes);
      expect(recovered.activeRoute, 'chat');
      expect(recovered.maxOutputTokens, 4096);
      expect(recovered.reasoningEffort, isNull);
      // The gone route's values are kept under it, not lost.
      final parked = ModelRoutes.parked(recovered);
      expect(parked[RouteKind.gemini]?.maxOutputTokens, 32768);
      expect(parked.containsKey(RouteKind.chat), isFalse);
    });

    test('switching away never files its values under the primary', () {
      final moved = RouteSwitching.switchRoute(
        stranded(),
        routes,
        RouteKind.responses,
      );
      final parked = ModelRoutes.parked(moved);
      expect(parked[RouteKind.chat]?.maxOutputTokens, 4096);
      expect(parked[RouteKind.gemini]?.maxOutputTokens, 32768);
    });

    test('a model whose route is there is returned as is', () {
      final fine = model(activeRoute: 'responses');
      expect(identical(RouteSwitching.recoverMissingRoute(fine, routes), fine), isTrue);
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

  group('after a channel edit', () {
    final chatOnly = ChannelRoutes.create(
      Platforms.byId(Platforms.newapi),
      'https://relay.example.com',
      [RouteKind.chat],
    );
    final responsesFirst = routes.withPrimary(RouteKind.responses);

    test('a primary that changed but stayed pins its followers', () {
      final r = RouteSwitching.afterChannelEdit(
        [model()],
        routes,
        responsesFirst,
      );
      expect(r.pinned.single.activeRoute, RouteKind.chat.id);
      expect(r.moved, isEmpty);
    });

    test('a primary dropped with the old routes pins nothing', () {
      final onlyResponses = ChannelRoutes.create(
        Platforms.byId(Platforms.newapi),
        'https://relay.example.com',
        [RouteKind.responses],
      );
      final r = RouteSwitching.afterChannelEdit([model()], routes, onlyResponses);
      expect(r.pinned, isEmpty);
      expect(r.moved, isEmpty);
    });

    test('a rider of a removed route moves onto the primary, values parked', () {
      final rider = model(activeRoute: RouteKind.anthropic.id);
      final r = RouteSwitching.afterChannelEdit([rider], routes, chatOnly);
      final moved = r.moved.single;
      expect(moved.activeRoute, RouteKind.chat.id);
      expect(ModelRoutes.parked(moved).keys, contains(RouteKind.anthropic));
      expect(moved.id, rider.id);
    });

    test('a route already gone before the edit is left to the user', () {
      final lost = model(activeRoute: RouteKind.gemini.id);
      final r = RouteSwitching.afterChannelEdit([lost], routes, chatOnly);
      expect(r.moved, isEmpty);
    });
  });
}
