import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/llm_channel.dart';
import 'package:joycai_image_ai_toolkits/models/llm_model.dart';
import 'package:joycai_image_ai_toolkits/models/spec_rate.dart';
import 'package:joycai_image_ai_toolkits/services/catalogue/builtin_model_specs.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendors.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_draft.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/model_edit_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/private_data_dir.dart';
import '../../support/real_async.dart';

void main() {
  usePrivateDataDir('joycai_builtin_model_preset_ui_test');

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FeeGroupDraft.applyBuiltinPricing', () {
    test('loads token + image media pricing from GPT Image 2.6 preset', () {
      final draft = FeeGroupDraft(null);
      addTearDown(draft.dispose);

      final spec = BuiltinModelSpecs.byId('gpt-image-2.6-flare')!;
      draft.applyBuiltinPricing(spec);

      expect(draft.name, 'GPT Image 2.6 Flare');
      expect(draft.billingMode, 'token');
      expect(draft.inputPriceCtrl.text, '5.0');
      expect(draft.outputPriceCtrl.text, '30.0');
      expect(draft.imageTokenInputCtrl.text, '8.0');
      expect(draft.imageTokenOutputCtrl.text, '30.0');
      expect(draft.canSave, isTrue);
    });

    test('loads spec pricing + input image fee from Seedream 5.0 Pro preset', () {
      final draft = FeeGroupDraft(null);
      addTearDown(draft.dispose);

      final spec = BuiltinModelSpecs.byId('doubao-seedream-5-0-pro')!;
      draft.applyBuiltinPricing(spec);

      expect(draft.billingMode, 'spec');
      expect(draft.outputUnit, OutputUnit.image);
      expect(draft.specRows.length, 3);
      expect(draft.otherPriceCtrl.text, '0.0900');
      expect(draft.inputImagePriceCtrl.text, '0.0030');
      expect(draft.inputFreeCtrl.text, '1');
      expect(draft.canSave, isTrue);
    });
  });

  group('ModelEditDialog built-in preset UI', () {
    testWidgets('fuzzy matches typed ID and applies preset parameters on tap', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final (appState, channelId) = await runAsyncRethrowing(tester, () async {
        final state = AppState();
        await state.refreshDataCache();
        for (final m in [...state.allModels]) {
          await state.deleteModel(m.id!);
        }
        for (final c in [...state.allChannels]) {
          await state.deleteChannel(c.id!);
        }
        final cid = await state.addChannel(
          LLMChannel(
            displayName: 'OpenAI',
            type: Vendors.openAIRest,
            endpoint: 'https://api.openai.com/v1',
            apiKey: 'sk-test',
          ),
        );
        return (state, cid);
      });

      final existing = LLMModel(
        id: 1,
        modelId: 'grok-4.7',
        modelName: 'Grok 4.7',
        tag: 'chat',
        channelId: channelId,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ModelEditDialog(
                l10n: AppLocalizations.of(context)!,
                appState: appState,
                model: existing,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fuzzy match banner appears automatically for `grok-4.7`.
      expect(find.text('Matched: Grok 4.7'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);

      // Tap Apply — populates context window (500000), max output (131072),
      // multimodal tag, and high reasoning effort.
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Applied: Grok 4.7'), findsOneWidget);
      expect(find.text('500000'), findsOneWidget);
      expect(find.text('131072'), findsOneWidget);

      // Manual preset picker opens and lets user apply another preset (e.g. Claude Opus 5.5).
      await tester.tap(find.text('Choose preset'));
      await tester.pumpAndSettle();
      expect(find.text('Select model preset'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'claude-opus-5-5');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude Opus 5.5').first);
      await tester.pumpAndSettle();

      expect(find.text('Applied: Claude Opus 5.5'), findsOneWidget);
      expect(find.text('1000000'), findsOneWidget);
      expect(find.text('128000'), findsOneWidget);

      // Clean up without saving to DB under fake async.
      await runAsyncRethrowing(tester, () async {});
    });
  });
}
