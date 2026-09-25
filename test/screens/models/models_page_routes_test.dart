import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/models/widgets/channel_row.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/app_route_badge.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_card.dart';

/// `D1f · 4a`: the models page names platforms and routes.
void main() {
  final relay = LLMChannel(
    id: 1,
    displayName: 'Relay',
    endpoint: 'https://relay.example.com/v1',
    apiKey: 'k',
    type: Vendors.newApiOpenAI,
  );
  final deepseek = LLMChannel(
    id: 2,
    displayName: 'DeepSeek',
    endpoint: 'https://api.deepseek.com',
    apiKey: 'k',
    type: Vendors.deepseek,
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(
          accent: AppConstants.presetThemes.values.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(body: SizedBox(width: 420, child: child)),
      ),
    );
  }

  LLMModel chat({String? activeRoute, int channelId = 1}) => LLMModel(
    id: 5,
    modelId: 'gpt-5.2',
    modelName: 'GPT-5.2',
    tag: 'chat',
    channelId: channelId,
    activeRoute: activeRoute,
  );

  testWidgets('a rail row names the platform and its routes', (tester) async {
    await pump(tester, ChannelRow(channel: relay, modelCount: 3));
    expect(find.text('New API'), findsOneWidget);
    final badges = tester.widgetList<AppRouteBadge>(find.byType(AppRouteBadge)).toList();
    expect(badges.first.label, 'Chat');
    expect(badges.first.state, RouteBadgeState.current);
    expect(badges.skip(1).every((b) => b.state == RouteBadgeState.configured), isTrue);
  });

  testWidgets('a card on a multi-route channel names its route', (tester) async {
    await pump(
      tester,
      ModelCard(
        model: chat(activeRoute: 'responses'),
        channel: relay,
      ),
    );
    expect(find.widgetWithText(AppRouteBadge, 'Responses'), findsOneWidget);
  });

  testWidgets('a card on a single-route channel names none', (tester) async {
    await pump(tester, ModelCard(model: chat(channelId: 2), channel: deepseek));
    expect(find.byType(AppRouteBadge), findsNothing);
  });

  testWidgets('a route the channel no longer offers is flagged', (tester) async {
    await pump(
      tester,
      ModelCard(
        model: chat(activeRoute: 'dashscope'),
        channel: relay,
      ),
    );
    expect(find.byIcon(Icons.link_off), findsOneWidget);
    expect(find.byType(AppRouteBadge), findsNothing);
  });
}
