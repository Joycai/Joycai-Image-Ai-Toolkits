// `A3e 5c–5e`: what the assistant shows of a preset's output kind — the
// marker on tiles, the empty chat's question, and the copy row under an
// analysis result. The panel's row is pinned beside the rest of its card, in
// `optimizer_a2_frames_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/assistant/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/services/llm/llm_types.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_neutral_marker.dart';
import 'package:provider/provider.dart';

SystemPrompt preset(int id, String title, PresetOutputKind kind) => SystemPrompt(
  id: id,
  title: title,
  content: 'Instructions for $title.',
  type: SystemPrompt.typeRefiner,
  outputKind: kind,
);

void main() {
  late AppLocalizations l10n;
  setUpAll(() async => l10n = await AppLocalizations.delegate.load(const Locale('en')));

  final presets = [
    preset(1, 'Photo enhance', PresetOutputKind.prompt),
    preset(2, 'Garment analysis', PresetOutputKind.analysis),
  ];

  Future<void> pumpChat(
    WidgetTester tester, {
    required PromptOptimizerSession session,
    PresetOutputKind selectedKind = PresetOutputKind.prompt,
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ui = WorkbenchUIState()..optimizerSession = session;
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkbenchUIState>.value(
        value: ui,
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
              isBusy: false,
              presetChoices: OptimizerPresetChoices(
                presets: presets,
                selectedId: selectedKind == PresetOutputKind.analysis ? 2 : 1,
                builtinSelected: false,
                selectedKind: selectedKind,
                onPick: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the empty chat', () {
    testWidgets('marks the analysis tile and no other', (tester) async {
      await pumpChat(tester, session: PromptOptimizerSession());
      expect(find.byType(AppNeutralMarker), findsOneWidget);
      expect(find.text(l10n.presetOutputAnalysisShort), findsOneWidget);
      // A prompt preset loaded: the question and the hint are the usual ones.
      expect(find.text(l10n.optEmptyPresetTitle), findsOneWidget);
      expect(find.text(l10n.optEmptyAnalysisExample1), findsNothing);
      expect(find.text(l10n.optChatHint), findsOneWidget);
    });

    for (final size in const [Size(1000, 800), Size(390, 800)]) {
      testWidgets('asks what to look at under an analysis preset · ${size.width.round()}', (
        tester,
      ) async {
        await pumpChat(
          tester,
          session: PromptOptimizerSession(),
          selectedKind: PresetOutputKind.analysis,
          size: size,
        );
        expect(find.text(l10n.optEmptyAnalysisTitle), findsOneWidget);
        expect(find.text(l10n.optEmptyPresetTitle), findsNothing);
        expect(find.text(l10n.optEmptyAnalysisExample2), findsOneWidget);
        expect(find.text(l10n.optChatHintAnalysis), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an example fills the composer, and sends nothing', (tester) async {
      final ctrl = TextEditingController();
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var sent = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<WorkbenchUIState>.value(
          value: WorkbenchUIState(),
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PromptOptimizerChatView(
                inputCtrl: ctrl,
                onSend: () => sent++,
                onRetry: () {},
                onApplyPrompt: (_) {},
                onApplyKbEdit: (_) {},
                onRejectKbEdit: (_) {},
                onAnswerAskUser: (_, _) {},
                isBusy: false,
                presetChoices: OptimizerPresetChoices(
                  presets: presets,
                  selectedId: 2,
                  builtinSelected: false,
                  selectedKind: PresetOutputKind.analysis,
                  onPick: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text(l10n.optEmptyAnalysisExample1));
      await tester.pump();
      expect(ctrl.text, l10n.optEmptyAnalysisExample1);
      expect(sent, 0);
    });

    testWidgets('a knowledge session is untouched by the panel\'s preset', (tester) async {
      await pumpChat(
        tester,
        session: PromptOptimizerSession(mode: AssistantMode.knowledgeBase),
        selectedKind: PresetOutputKind.analysis,
      );
      expect(find.text(l10n.optEmptyKbTitle), findsOneWidget);
      expect(find.text(l10n.optChatHint), findsOneWidget);
    });
  });

  group('an analysis result', () {
    PromptOptimizerSession sessionWith({required bool deliverable}) =>
        PromptOptimizerSession.fromStored(
          id: 's',
          mode: AssistantMode.systemPrompt,
          history: [
            LLMMessage(role: LLMRole.user, content: 'describe image 1'),
            LLMMessage(
              role: LLMRole.assistant,
              content: '## Overview\nA **short** jacket.',
              deliverable: deliverable,
            ),
          ],
        );

    testWidgets('can be copied, as the Markdown it was written in', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpChat(
        tester,
        session: sessionWith(deliverable: true),
        selectedKind: PresetOutputKind.analysis,
      );
      expect(
        find.text(l10n.optResultMeta('## Overview\nA **short** jacket.'.length)),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.optCopy));
      await tester.pump();
      expect(copied, '## Overview\nA **short** jacket.');
      // Let the snackbar run out before the test ends.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a remark has no copy row', (tester) async {
      await pumpChat(tester, session: sessionWith(deliverable: false));
      expect(find.text(l10n.optCopy), findsNothing);
    });

    testWidgets('fits a phone', (tester) async {
      await pumpChat(
        tester,
        session: sessionWith(deliverable: true),
        selectedKind: PresetOutputKind.analysis,
        size: const Size(390, 800),
      );
      expect(find.text(l10n.optCopy), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
