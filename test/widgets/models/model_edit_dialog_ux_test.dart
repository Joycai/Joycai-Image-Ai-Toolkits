import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/l10n/localizations_delegates.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_controls/model_edit_fields.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_controls/model_edit_track_slider.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_dialog.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_protocol_section.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_segmented_control.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_switch.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/model_tag_chip.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  usePrivateDataDir('joycai_model_edit_dialog_ux_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(AppState, int)> seedChannel(
    WidgetTester tester, {
    required String name,
    required String vendorType,
    required String endpoint,
  }) async {
    return runAsyncRethrowing(tester, () async {
      final state = AppState();
      await state.refreshDataCache();
      for (final m in [...state.allModels]) {
        await state.deleteModel(m.id!);
      }
      for (final c in [...state.allChannels]) {
        await state.deleteChannel(c.id!);
      }
      final channelId = await state.addChannel(
        LLMChannel(displayName: name, type: vendorType, endpoint: endpoint, apiKey: 'sk-test'),
      );
      return (state, channelId);
    });
  }

  Future<void> pumpEditor(
    WidgetTester tester, {
    required AppState appState,
    required LLMModel model,
    Brightness brightness = Brightness.light,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = buildAppTheme(
      accent: AppConstants.presetThemes.values.first,
      brightness: brightness,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: ModelEditDialog(
              l10n: AppLocalizations.of(context)!,
              appState: appState,
              model: model,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('image model hides chat/reasoning controls, shows live header & transport collapse', (
    tester,
  ) async {
    final (state, channelId) = await seedChannel(
      tester,
      name: 'Joycai',
      vendorType: Vendors.newApiOpenAI,
      endpoint: 'https://relay.example.com/v1',
    );
    final model = await runAsyncRethrowing(tester, () async {
      final id = await state.addModel(
        LLMModel(
          modelId: 'gpt-image-2.5-sunburst',
          modelName: 'gpt-image-2.5-sunburst',
          tag: 'image',
          channelId: channelId,
        ),
      );
      return state.allModels.firstWhere((m) => m.id == id);
    });

    await pumpEditor(tester, appState: state, model: model);

    // Card preview and unrelated chat/agent/reasoning controls are absent.
    expect(find.text('Card preview'), findsNothing);
    expect(find.text('Context Window'), findsNothing);
    expect(find.text('Reasoning Effort'), findsNothing);
    expect(find.text('Image / video input (Multimodal)'), findsNothing);
    expect(find.text('View all reference images'), findsNothing);

    // 3-way kind control (Chat / Image / Video) and live header summary.
    final seg = tester.widget<AppSegmentedControl<String>>(
      find.byType(AppSegmentedControl<String>),
    );
    expect(seg.segments.map((s) => s.value), ['chat', 'image', 'video']);
    expect(seg.value, 'image');
    expect(find.byType(ModelProtocolSection), findsOneWidget);
    expect(find.byType(ModelKindBadge), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data?.contains('gpt-image-2.5-sunburst') ?? false) &&
            (w.data?.contains('Default pricing') ?? false),
      ),
      findsOneWidget,
    );

    // Transport compatibility starts collapsed and expands cleanly.
    expect(find.text('Transport Compatibility'), findsOneWidget);
    expect(find.text('Stream On · Standard On'), findsOneWidget);
    expect(find.text('Supports Streaming'), findsNothing);

    await tester.ensureVisible(find.text('Transport Compatibility'));
    await tester.tap(find.text('Transport Compatibility'));
    await tester.pumpAndSettle();
    expect(find.text('Supports Streaming'), findsOneWidget);
    expect(find.text('Supports Standard Request'), findsOneWidget);

    await runAsyncRethrowing(tester, () async {});
  });

  testWidgets('chat model merges multimodal toggle and nests view-all-images', (tester) async {
    final (state, channelId) = await seedChannel(
      tester,
      name: 'OpenAI',
      vendorType: Vendors.openAIRest,
      endpoint: 'https://api.openai.com/v1',
    );
    final model = await runAsyncRethrowing(tester, () async {
      final id = await state.addModel(
        LLMModel(
          modelId: 'gpt-4o',
          modelName: 'GPT-4o',
          tag: 'chat',
          channelId: channelId,
          contextWindow: 128000,
        ),
      );
      return state.allModels.firstWhere((m) => m.id == id);
    });

    await pumpEditor(tester, appState: state, model: model);

    expect(find.text('TOKEN BUDGET'), findsOneWidget);
    expect(find.text('BEHAVIOR & EXTENSIONS'), findsOneWidget);
    expect(find.text('Image / video input (Multimodal)'), findsOneWidget);
    // Pure chat hides View all reference images until multimodal is switched on.
    expect(find.text('View all reference images'), findsNothing);

    final multimodalRow = find.ancestor(
      of: find.text('Image / video input (Multimodal)'),
      matching: find.byType(ModelEditToggleRow),
    );
    await tester.ensureVisible(multimodalRow);
    await tester.tap(find.descendant(of: multimodalRow, matching: find.byType(AppSwitch)));
    await tester.pumpAndSettle();

    expect(find.text('View all reference images'), findsOneWidget);
    final badge = tester.widget<ModelKindBadge>(find.byType(ModelKindBadge));
    expect(badge.tag, 'multimodal');

    await inRealAsyncUntil(
      tester,
      () => tester.tap(find.text('Save').last),
      until: () => state.allModels.any((m) => m.id == model.id && m.tag == 'multimodal'),
    );
    final saved = await runAsyncRethrowing(tester, () async {
      await state.refreshDataCache();
      return state.allModels.firstWhere((m) => m.id == model.id);
    });
    expect(saved.tag, 'multimodal');
  });

  testWidgets('unsupported reasoning collapses to a quiet 1-line row without slider', (
    tester,
  ) async {
    final (state, channelId) = await seedChannel(
      tester,
      name: 'Google AI Studio',
      vendorType: Vendors.googleRest,
      endpoint: 'https://generativelanguage.googleapis.com/v1beta',
    );
    final model = await runAsyncRethrowing(tester, () async {
      final id = await state.addModel(
        LLMModel(
          modelId: 'gemini-1.5-pro',
          modelName: 'Gemini 1.5 Pro',
          tag: 'chat',
          channelId: channelId,
        ),
      );
      return state.allModels.firstWhere((m) => m.id == id);
    });

    await pumpEditor(tester, appState: state, model: model);

    expect(find.text('Not supported by this model or protocol'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is ModelEditTrackSlider && w.semanticLabel == 'Reasoning Effort',
      ),
      findsNothing,
    );

    await runAsyncRethrowing(tester, () async {});
  });

  testWidgets(
    'switching Chat (multimodal) -> Image -> Chat preserves multimodal and saves cleanly',
    (tester) async {
      final (state, channelId) = await seedChannel(
        tester,
        name: 'OpenAI',
        vendorType: Vendors.openAIRest,
        endpoint: 'https://api.openai.com/v1',
      );
      final model = await runAsyncRethrowing(tester, () async {
        final id = await state.addModel(
          LLMModel(
            modelId: 'my-model',
            modelName: 'My Model',
            tag: 'multimodal',
            channelId: channelId,
          ),
        );
        return state.allModels.firstWhere((m) => m.id == id);
      });

      await pumpEditor(tester, appState: state, model: model);
      expect(tester.widget<ModelKindBadge>(find.byType(ModelKindBadge)).tag, 'multimodal');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data?.contains('my-model') ?? false) &&
              (w.data?.contains('No Fee Group') ?? false),
        ),
        findsOneWidget,
      );

      // Select Specify with blank context input; switching to Image must still
      // save cleanly without storing 0 (unlimited) contextWindow.
      await tester.tap(find.text('Specify').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Image'));
      await tester.pumpAndSettle();
      expect(tester.widget<ModelKindBadge>(find.byType(ModelKindBadge)).tag, 'image');

      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(tester.widget<ModelKindBadge>(find.byType(ModelKindBadge)).tag, 'multimodal');

      // Switch back to Image and confirm Save works with context hidden.
      await tester.tap(find.text('Image'));
      await tester.pumpAndSettle();
      await inRealAsyncUntil(
        tester,
        () => tester.tap(find.text('Save').last),
        until: () => state.allModels.any((m) => m.id == model.id && m.tag == 'image'),
      );
      final saved = await runAsyncRethrowing(tester, () async {
        await state.refreshDataCache();
        return state.allModels.firstWhere((m) => m.id == model.id);
      });
      expect(saved.contextWindow, isNull);
    },
  );

  testWidgets('renders without overflow in dark theme and phone layout (390x844)', (tester) async {
    final (state, channelId) = await seedChannel(
      tester,
      name: 'OpenAI',
      vendorType: Vendors.openAIRest,
      endpoint: 'https://api.openai.com/v1',
    );
    final model = await runAsyncRethrowing(tester, () async {
      final id = await state.addModel(
        LLMModel(
          modelId: 'gpt-4o',
          modelName: 'GPT-4o',
          tag: 'multimodal',
          channelId: channelId,
          contextWindow: 128000,
          maxOutputTokens: 16384,
        ),
      );
      return state.allModels.firstWhere((m) => m.id == id);
    });

    await pumpEditor(
      tester,
      appState: state,
      model: model,
      brightness: Brightness.dark,
      size: const Size(390, 844),
    );
    expect(find.byType(AppSegmentedControl<String>), findsOneWidget);
    expect(tester.widget<ModelKindBadge>(find.byType(ModelKindBadge)).tag, 'multimodal');
    expect(tester.takeException(), isNull);

    await runAsyncRethrowing(tester, () async {});
  });

  testWidgets('pinned non-streaming image protocol shows Ignored in collapsed transport summary', (
    tester,
  ) async {
    final (state, channelId) = await seedChannel(
      tester,
      name: 'Relay',
      vendorType: Vendors.newApiOpenAI,
      endpoint: 'https://relay.example.com/v1',
    );
    final model = await runAsyncRethrowing(tester, () async {
      final id = await state.addModel(
        LLMModel(
          modelId: 'img-fast',
          modelName: 'Img Fast',
          tag: 'image',
          channelId: channelId,
          wireProtocol: 'openai-images',
        ),
      );
      return state.allModels.firstWhere((m) => m.id == id);
    });

    await pumpEditor(tester, appState: state, model: model);

    expect(find.text('Stream Ignored · Standard On'), findsOneWidget);

    await runAsyncRethrowing(tester, () async {});
  });
}
