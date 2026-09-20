// `A3e 5f`: a model that takes no images answers blind. The log used to be
// the only place that said so; now the conversation does — once per model.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

const _refs = [
  {'path': '/nowhere/a.png', 'name': 'a.png'},
  {'path': '/nowhere/b.png', 'name': 'b.png'},
];

void main() {
  usePrivateDataDir('joycai_images_not_offered_test');
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  tearDown(() => PromptOptimizerAgent.debugRequestOverride = null);

  Future<void> turn(
    PromptOptimizerSession session, {
    required int model,
    required bool seesImages,
    List<Map<String, String>> refs = _refs,
  }) async {
    PromptOptimizerAgent.debugRequestOverride =
        (messages, tools, options) async => LLMResponse(text: 'ok');
    session.addUserTurn('what is in reference image 1?');
    await PromptOptimizerAgent.runTurn(
      session: session,
      modelIdentifier: model,
      referenceImages: refs,
      acceptsImageInput: seesImages,
    );
  }

  List<OptimizerChatEntry> notices(PromptOptimizerSession session) => [
        for (final e in session.transcript)
          if (e.text == PromptOptimizerAgent.imagesNotOfferedNoticeToken) e,
      ];

  test('a blind model with images to read says so, between the question and the answer', () async {
    final session = PromptOptimizerSession();
    await turn(session, model: 7, seesImages: false);

    final notice = notices(session).single;
    expect(notice.note, '2');
    expect(notice.modelDbId, 7);
    expect([for (final e in session.transcript) e.kind], [
      OptimizerEntryKind.user,
      OptimizerEntryKind.notice,
      OptimizerEntryKind.assistant,
    ]);
  });

  test('says it once per model, and again for another blind model', () async {
    final session = PromptOptimizerSession();
    await turn(session, model: 7, seesImages: false);
    await turn(session, model: 7, seesImages: false);
    expect(notices(session), hasLength(1));

    await turn(session, model: 8, seesImages: false);
    expect([for (final e in notices(session)) e.modelDbId], [7, 8]);
  });

  test('says nothing when there is nothing to see, or a model that sees', () async {
    final session = PromptOptimizerSession();
    await turn(session, model: 7, seesImages: false, refs: const []);
    await turn(session, model: 7, seesImages: true);
    expect(notices(session), isEmpty);
  });

  testWidgets('the card names the count and leads to the model that ran', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final session = PromptOptimizerSession();
    await tester.runAsync(() => turn(session, model: 7, seesImages: false));

    int? opened;
    await tester.pumpWidget(ChangeNotifierProvider<WorkbenchUIState>.value(
      value: WorkbenchUIState()..optimizerSession = session,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PromptOptimizerChatView(
            inputCtrl: TextEditingController(),
            onSend: () {},
            onRetry: () {},
            onApplyPrompt: (_) {},
            onApplyKbEdit: (_) {},
            onRejectKbEdit: (_) {},
            onAnswerAskUser: (_, _) {},
            onOpenModelSettings: (id) => opened = id,
            isBusy: false,
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text(l10n.optImagesNotOfferedTitle), findsOneWidget);
    expect(find.text(l10n.optImagesNotOfferedBody(2)), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(l10n.optImagesNotOfferedAction));
    expect(opened, 7);
  });
}
