import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/app_route_badge.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// `D1f · 4d`: the model editor's route strip and switching.
void main() {
  usePrivateDataDir('joycai_model_edit_routes_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A New API relay (Chat Completions + Responses) and one chat model on
  /// its Chat route with a 65536 cap and High effort. Seeded through
  /// runAsync: sqflite does real I/O the fake-async zone never completes.
  Future<(AppState, LLMModel)> seed(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final state = AppState();
      await state.refreshDataCache();
      for (final m in [...state.allModels]) {
        await state.deleteModel(m.id!);
      }
      for (final c in [...state.allChannels]) {
        await state.deleteChannel(c.id!);
      }
      final channelId = await state.addChannel({
        'display_name': 'Relay',
        'type': Vendors.newApiOpenAI,
        'endpoint': 'https://relay.example.com/v1',
        'api_key': 'k',
      });
      final modelId = await state.addModel({
        'model_id': 'gpt-5.2',
        'model_name': 'GPT-5.2',
        'tag': 'chat',
        'channel_id': channelId,
        'max_output_tokens': 65536,
        'reasoning_effort': 'high',
        'enable_thinking': 1,
      });
      return (state, state.allModels.firstWhere((m) => m.id == modelId));
    }))!;
  }

  Future<void> pump(WidgetTester tester, AppState state, LLMModel model,
      {Size size = const Size(1400, 1100)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ModelEditDialog(
            l10n: AppLocalizations.of(context)!,
            appState: state,
            model: model,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Finder strip(String label) => find.byWidgetPredicate(
    (w) => w is AppRouteBadge && w.label == label && w.onTap != null,
  );

  testWidgets('a chat model on a multi-route channel has a route strip',
      (tester) async {
    final (state, model) = await seed(tester);
    await pump(tester, state, model);

    expect(strip('Chat Completions'), findsOneWidget);
    expect(strip('Responses'), findsOneWidget);
    expect(
      tester.widget<AppRouteBadge>(strip('Chat Completions')).state,
      RouteBadgeState.current,
    );
    // The protocol dropdown gives way to it.
    expect(find.text('Request method · Interface protocol'), findsNothing);
  });

  testWidgets('a route never set up previews, then switches to blank',
      (tester) async {
    final (state, model) = await seed(tester);
    await pump(tester, state, model);

    await tester.tap(strip('Responses'));
    await tester.pumpAndSettle();
    expect(find.text('Switch to Responses · these parameters change'),
        findsOneWidget);
    expect(find.text('Not set · not sent'), findsWidgets);

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AppRouteBadge>(strip('Responses')).state,
      RouteBadgeState.current,
    );

    // Saved: on Responses with nothing set, the Chat values parked.
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(() async {
      await state.refreshDataCache();
      return state.allModels.firstWhere((m) => m.id == model.id);
    }))!;
    expect(saved.activeRoute, 'responses');
    expect(saved.maxOutputTokens, isNull);
    expect(saved.reasoningEffort, isNull);
    final parked = ModelRoutes.parked(saved)[RouteKind.chat]!;
    expect(parked.maxOutputTokens, 65536);
    expect(parked.reasoningEffort, 'high');
    // The compat pin an older build can route the same way.
    expect(saved.wireProtocol, 'openai-responses');
  });

  testWidgets('back to a route set up switches at once, values restored',
      (tester) async {
    final (state, model) = await seed(tester);
    final parkedOnResponses = model.withRouteState(
      activeRoute: 'chat',
      routeParams: ModelRoutes.encodeParked({
        RouteKind.responses: const RouteParams(maxOutputTokens: 8000),
      }),
      wireProtocol: null,
      maxOutputTokens: model.maxOutputTokens,
      enableThinking: model.enableThinking,
      reasoningEffort: model.reasoningEffort,
    );
    await pump(tester, state, parkedOnResponses);

    await tester.tap(strip('Responses'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Switch to Responses'), findsNothing);
    expect(find.widgetWithText(TextField, '8000'), findsOneWidget);
  });

  // `4d` 联网搜索各线路, three answers: New API's Anthropic face sends ④'s
  // server tool but no live run has seen a relay act on it (help); its Chat
  // face has no web search to send (block).
  testWidgets('the web-search matrix marks a route never tested', (tester) async {
    final (state, model) = (await tester.runAsync(() async {
      final state = AppState();
      await state.refreshDataCache();
      for (final m in [...state.allModels]) {
        await state.deleteModel(m.id!);
      }
      for (final c in [...state.allChannels]) {
        await state.deleteChannel(c.id!);
      }
      final routes = ChannelRoutes.resolve(
        Vendors.newApiAnthropic,
        'https://relay.example.com/v1',
        null,
      ).withRoute(RouteKind.chat);
      final channelId = await state.addChannel({
        'display_name': 'Relay',
        'type': routes.primaryVendorId,
        'endpoint': routes.primaryAddress,
        'routes': routes.encode(),
        'api_key': 'k',
      });
      final modelId = await state.addModel({
        'model_id': 'claude-sonnet-4-5',
        'model_name': 'Sonnet',
        'tag': 'chat',
        'channel_id': channelId,
        'enable_web_search': 1,
      });
      return (state, state.allModels.firstWhere((m) => m.id == modelId));
    }))!;
    await pump(tester, state, model);

    AppRouteBadge cell(String label) => tester.widget<AppRouteBadge>(find.byWidgetPredicate(
      (w) => w is AppRouteBadge && w.label == label && w.onTap == null,
    ));
    expect(cell('Anth').trailingIcon, Icons.help_outline);
    expect(cell('Anth').state, RouteBadgeState.off);
    expect(cell('Chat').trailingIcon, Icons.block);
    expect(find.textContaining("hasn't been tested"), findsOneWidget);
  });

  // `4g`: a phone's strip scrolls sideways instead of wrapping.
  testWidgets('on a phone the route strip scrolls sideways', (tester) async {
    final (state, model) = await seed(tester);
    await pump(tester, state, model, size: const Size(390, 844));
    final scroller = find.ancestor(
      of: strip('Chat Completions'),
      matching: find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
    );
    expect(scroller, findsOneWidget);
    expect(find.ancestor(of: strip('Chat Completions'), matching: find.byType(Wrap)),
        findsNothing);

    await pump(tester, state, model);
    expect(find.ancestor(of: strip('Chat Completions'), matching: find.byType(Wrap)),
        findsOneWidget);
  });
}
