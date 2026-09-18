import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/models/widgets/channel_merge_review.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

/// `D1f · 4f`: the merge prompt and its one-group-at-a-time review.
void main() {
  usePrivateDataDir('joycai_channel_merge_review_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Two New API channels on one host and key — OpenAI and Claude format —
  /// each with a model, one of them a namesake.
  Future<AppState> seed(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final state = AppState();
      await state.refreshDataCache();
      for (final m in [...state.allModels]) {
        await state.deleteModel(m.id!);
      }
      for (final c in [...state.allChannels]) {
        await state.deleteChannel(c.id!);
      }
      final openai = await state.addChannel({
        'display_name': 'Relay',
        'type': Vendors.newApiOpenAI,
        'endpoint': 'https://relay.example.com/v1',
        'api_key': 'sk-shared',
      });
      final claude = await state.addChannel({
        'display_name': 'Relay (Claude)',
        'type': Vendors.newApiAnthropic,
        'endpoint': 'https://relay.example.com/v1',
        'api_key': 'sk-shared',
      });
      await state.addModel({
        'model_id': 'claude-sonnet-4-5',
        'model_name': 'Sonnet',
        'tag': 'chat',
        'channel_id': openai,
      });
      await state.addModel({
        'model_id': 'claude-sonnet-4-5',
        'model_name': 'Sonnet (Claude)',
        'tag': 'chat',
        'channel_id': claude,
      });
      await state.addModel({
        'model_id': 'claude-opus-4-1',
        'model_name': 'Opus',
        'tag': 'chat',
        'channel_id': claude,
      });
      return state;
    }))!;
  }

  Future<void> pump(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ChannelMergeBanner(
            count: mergeCandidatesOf(state).length,
            onReview: () => reviewChannelMerges(context, state),
          ),
        ),
      ),
    ));
  }

  /// Taps through a review whose steps do real database I/O.
  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    // Real I/O and frames in turn: each database step resolves outside the
    // fake clock, and the dialog it leads to needs frames to appear.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('the prompt counts the groups', (tester) async {
    final state = await seed(tester);
    await pump(tester, state);
    expect(find.text('1 group of channels can be merged'), findsOneWidget);
  });

  testWidgets('the preview says what merges and what moves', (tester) async {
    final state = await seed(tester);
    await pump(tester, state);
    await tapAndSettle(tester, find.text('Review'));

    expect(find.text('Merge channels'), findsOneWidget);
    expect(find.text('Relay'), findsOneWidget);
    expect(find.text('Relay (Claude)'), findsOneWidget);
    expect(find.text('Anthropic · Merged in'), findsOneWidget);
    expect(find.text('Same model, merged · Anthropic parameters carried over'),
        findsOneWidget);
    expect(find.text('Moved · pinned to Anthropic'), findsOneWidget);
  });

  testWidgets('skipping merges nothing; merging leaves one channel',
      (tester) async {
    final state = await seed(tester);
    await pump(tester, state);

    await tapAndSettle(tester, find.text('Review'));
    await tapAndSettle(tester, find.text('Skip this group'));
    expect(find.text('Merge channels'), findsNothing);
    expect(state.allChannels, hasLength(2));

    await tapAndSettle(tester, find.text('Review'));
    await tapAndSettle(tester, find.text('Merge'));
    await tester.runAsync(state.refreshDataCache);
    expect(state.allChannels, hasLength(1));
    expect(
      RoutedChannel.routesOf(state.allChannels.single).has(RouteKind.anthropic),
      isTrue,
    );
    expect(state.allModels.map((m) => m.modelId).toSet(),
        {'claude-sonnet-4-5', 'claude-opus-4-1'});
    expect(state.allModels, hasLength(2));
  });
}
