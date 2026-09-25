import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/models/widgets/channel_route_table.dart';
import 'package:joycai_image_ai_toolkits/services/llm/channel_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_dispatcher.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';

/// `D1f · 4c`: the channel editor's route table.
void main() {
  late ChannelRoutes current;

  Future<void> pump(
    WidgetTester tester,
    ChannelRoutes routes, {
    Map<RouteKind, int> inUse = const {},
  }) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    current = routes;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => ChannelRouteTable(
              routes: current,
              onChanged: (r) => setState(() => current = r),
              modelsOnRoute: (k) => inUse[k] ?? 0,
              onProbe: (_) {},
            ),
          ),
        ),
      ),
    ));
  }

  final relay = ChannelRoutes.resolve(
    Vendors.newApiOpenAI,
    'https://relay.example.com/v1',
    null,
  );

  testWidgets('each route shows the address a request goes to',
      (tester) async {
    await pump(tester, relay);
    expect(find.text('Chat Completions · Primary'), findsOneWidget);
    expect(
      find.text('POST ${LLMDispatcher.chatRequestUrl(
        RouteKind.chat.face,
        'https://relay.example.com/v1',
      )}'),
      findsOneWidget,
    );
    expect(find.text('POST https://relay.example.com/v1/chat/completions'),
        findsOneWidget);
  });

  testWidgets('a route the platform offers can be enabled', (tester) async {
    await pump(tester, relay);
    expect(relay.has(RouteKind.anthropic), isFalse);
    expect(find.text('Anthropic'), findsOneWidget);
    await tester.tap(find.text('Enable').first);
    await tester.pump();
    expect(current.kinds.length, relay.kinds.length + 1);
  });

  testWidgets('an edited path says so and restores to the default',
      (tester) async {
    await pump(tester, relay.withPath(RouteKind.chat, '/openai/v1'));
    expect(find.text('Edited · default /v1'), findsOneWidget);
    expect(
      find.text('POST https://relay.example.com/openai/v1/chat/completions'),
      findsOneWidget,
    );
    await tester.tap(find.text('Restore default'));
    await tester.pump();
    expect(current.entry(RouteKind.chat)!.path, isNull);
    expect(find.text('Default /v1'), findsWidgets);
  });

  testWidgets('a path stored empty reads as the host itself', (tester) async {
    await pump(tester, relay.withPath(RouteKind.chat, ''));
    expect(find.text('Host itself · default /v1'), findsOneWidget);
    expect(find.text('(the host itself)'), findsOneWidget);
    expect(find.text('POST https://relay.example.com/chat/completions'),
        findsOneWidget);
    await tester.tap(find.text('Restore default'));
    await tester.pump();
    expect(current.primary.path, isNull);
  });

  testWidgets("a custom host can put a route at its root; a relay's layout is known",
      (tester) async {
    await pump(tester, relay);
    expect(find.text('Use host itself'), findsNothing);

    final custom = ChannelRoutes.resolve(
        Vendors.openAIRest, 'https://my.example.com/v1', null);
    expect(custom.platform.id, Platforms.custom);
    await pump(tester, custom);
    final offered = find.text('Use host itself').evaluate().length;
    expect(offered, custom.entries.length);
    await tester.tap(find.text('Use host itself').first);
    await tester.pump();
    expect(current.primary.path, '');
    expect(current.primaryAddress, 'https://my.example.com');
    // Offered only while a route is on its default path.
    expect(find.text('Use host itself'), findsNWidgets(offered - 1));
  });

  testWidgets('a whole address is a host of its own', (tester) async {
    await pump(
      tester,
      relay.withPath(RouteKind.chat, 'https://chat.relay.example.com/v1'),
    );
    expect(find.text('Own host'), findsOneWidget);
  });

  testWidgets("an official host's default route is locked", (tester) async {
    await pump(
      tester,
      ChannelRoutes.resolve(Vendors.openAIRest, 'https://api.openai.com/v1', null),
    );
    expect(find.text('Official address, locked'), findsWidgets);
  });

  testWidgets('a route in use cannot be turned off', (tester) async {
    final two = relay.withRoute(RouteKind.anthropic);
    await pump(tester, two, inUse: {RouteKind.anthropic: 2});
    // Blocked, and saying why: the one in use, and the primary.
    expect(
      find.byTooltip(
        "The primary route can't be turned off — make another route primary first",
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip("2 models use this route, so it can't be turned off"),
      findsOneWidget,
    );
  });

  testWidgets('making a route primary moves it first', (tester) async {
    final two = relay.withRoute(RouteKind.anthropic);
    await pump(tester, two);
    await tester.tap(find.byIcon(Icons.star_outline).last);
    await tester.pump();
    expect(current.primary.kind, RouteKind.anthropic);
  });
}
