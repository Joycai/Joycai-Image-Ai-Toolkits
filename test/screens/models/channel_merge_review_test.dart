import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/screens/models/widgets/channel_merge_review.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/channel_merge_executor.dart';
import 'package:joycai_image_ai_toolkits/services/llm/model_routes.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/platforms.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

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
    return runAsyncRethrowing(tester, () async {
      final state = AppState();
      await state.refreshDataCache();
      for (final m in [...state.allModels]) {
        await state.deleteModel(m.id!);
      }
      for (final c in [...state.allChannels]) {
        await state.deleteChannel(c.id!);
      }
      final openai = await state.addChannel(
        LLMChannel(
          displayName: 'Relay',
          type: Vendors.newApiOpenAI,
          endpoint: 'https://relay.example.com/v1',
          apiKey: 'sk-shared',
        ),
      );
      final claude = await state.addChannel(
        LLMChannel(
          displayName: 'Relay (Claude)',
          type: Vendors.newApiAnthropic,
          endpoint: 'https://relay.example.com/v1',
          apiKey: 'sk-shared',
        ),
      );
      await state.addModel(
        LLMModel(modelId: 'claude-sonnet-4-5', modelName: 'Sonnet', tag: 'chat', channelId: openai),
      );
      await state.addModel(
        LLMModel(
          modelId: 'claude-sonnet-4-5',
          modelName: 'Sonnet (Claude)',
          tag: 'chat',
          channelId: claude,
        ),
      );
      await state.addModel(
        LLMModel(modelId: 'claude-opus-4-1', modelName: 'Opus', tag: 'chat', channelId: claude),
      );
      return state;
    });
  }

  Future<void> pump(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
  }

  /// Taps through a review whose steps do real database I/O: the tap and the
  /// work it starts in real async, waited for by what it ends in ([until]),
  /// then the frames the dialog it leads to needs to appear.
  Future<void> tapAndSettle(WidgetTester tester, Finder f, {required bool Function() until}) async {
    await inRealAsyncUntil(tester, () => tester.tap(f), until: until);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  bool reviewOpen() => find.text('Merge channels').evaluate().isNotEmpty;

  group('the reference note says each kind on its own', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final zh = lookupAppLocalizations(const Locale('zh'));

    test('two kinds', () {
      const refs = MergeReferences(selections: 3, records: 128);
      expect(mergeReferencesText(zh, refs, 'R'), startsWith('3 处已选的模型与 128 条用量记录会改指向'));
      expect(
        mergeReferencesText(en, refs, 'R'),
        startsWith('3 saved model selections and 128 usage records will point'),
      );
    });

    test('three kinds, and a kind with none left out', () {
      expect(
        mergeReferencesText(en, const MergeReferences(selections: 1, records: 2, links: 1), 'R'),
        startsWith('1 saved model selection, 2 usage records and 1 model link in'),
      );
      expect(
        mergeReferencesText(en, const MergeReferences(links: 2), 'R'),
        startsWith('2 model links in assistant conversations will point'),
      );
    });

    test('none', () {
      expect(
        mergeReferencesText(en, const MergeReferences(), 'R'),
        startsWith('Nothing saved points'),
      );
    });
  });

  testWidgets('the prompt counts the groups', (tester) async {
    final state = await seed(tester);
    await pump(tester, state);
    expect(find.text('1 group of channels can be merged'), findsOneWidget);
  });

  testWidgets('the preview says what merges and what moves', (tester) async {
    final state = await seed(tester);
    await pump(tester, state);
    await tapAndSettle(tester, find.text('Review'), until: reviewOpen);

    expect(find.text('Merge channels'), findsOneWidget);
    expect(find.text('Relay'), findsOneWidget);
    expect(find.text('Relay (Claude)'), findsOneWidget);
    expect(find.text('Anthropic · Merged in'), findsOneWidget);
    expect(find.text('Same model, merged · Anthropic parameters carried over'), findsOneWidget);
    expect(find.text('Moved · pinned to Anthropic'), findsOneWidget);
  });

  testWidgets('skipping merges nothing; merging leaves one channel', (tester) async {
    final state = await seed(tester);
    await pump(tester, state);

    await tapAndSettle(tester, find.text('Review'), until: reviewOpen);
    // The only group there is, so skipping it ends the review without the
    // reference count a next group would read: nothing here for real async.
    await tester.tap(find.text('Skip this group'));
    await tester.pumpAndSettle();
    expect(find.text('Merge channels'), findsNothing);
    expect(state.allChannels, hasLength(2));

    await tapAndSettle(tester, find.text('Review'), until: reviewOpen);
    await tapAndSettle(tester, find.text('Merge'), until: () => state.allChannels.length == 1);
    expect(state.allChannels, hasLength(1));
    expect(RoutedChannel.routesOf(state.allChannels.single).has(RouteKind.anthropic), isTrue);
    expect(state.allModels.map((m) => m.modelId).toSet(), {'claude-sonnet-4-5', 'claude-opus-4-1'});
    expect(state.allModels, hasLength(2));
  });
}
