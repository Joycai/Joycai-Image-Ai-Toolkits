// `A3d 4c`: the empty chat says what *this* mode does, and what it offers is
// a selection or a draft — never a send.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/prompt_optimizer_view.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:provider/provider.dart';

void main() {
  Future<AppLocalizations> en() => AppLocalizations.delegate.load(const Locale('en'));

  final presets = <SystemPrompt>[
    for (var i = 1; i <= 6; i++)
      SystemPrompt(id: i, title: 'Preset $i', content: '# H\n\nDoes thing $i.', type: 'refiner'),
  ];

  Future<({TextEditingController input, List<int> sends})> pump(
    WidgetTester tester,
    AssistantMode mode, {
    OptimizerPresetChoices? choices,
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ui = WorkbenchUIState()..optimizerSession = PromptOptimizerSession(mode: mode);
    final input = TextEditingController();
    final sends = <int>[];
    await tester.pumpWidget(ChangeNotifierProvider<WorkbenchUIState>.value(
      value: ui,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PromptOptimizerChatView(
            inputCtrl: input,
            onSend: () => sends.add(1),
            onRetry: () {},
            onApplyPrompt: (_) {},
            onApplyKbEdit: (_) {},
            onRejectKbEdit: (_) {},
            onAnswerAskUser: (_, _) {},
            isBusy: false,
            presetChoices: choices,
          ),
        ),
      ),
    ));
    await tester.pump();
    return (input: input, sends: sends);
  }

  testWidgets('each mode has its own title', (tester) async {
    final l10n = await en();
    for (final (mode, title) in [
      (AssistantMode.systemPrompt, l10n.optEmptyPresetTitle),
      (AssistantMode.knowledgeBase, l10n.optEmptyKbTitle),
      (AssistantMode.knowledgeEdit, l10n.optEmptyKbEditTitle),
    ]) {
      await pump(tester, mode);
      expect(find.text(title), findsOneWidget, reason: mode.name);
    }
  });

  testWidgets('four tiles, the loaded one marked, and picking selects without sending',
      (tester) async {
    final picked = <SystemPrompt?>[];
    final host = await pump(
      tester,
      AssistantMode.systemPrompt,
      choices: OptimizerPresetChoices(
        presets: presets,
        selectedId: 2,
        builtinSelected: false,
        onPick: picked.add,
        onShowAll: () {},
      ),
    );
    final l10n = await en();

    expect(find.text('Preset 4'), findsOneWidget);
    expect(find.text('Preset 5'), findsNothing);
    expect(find.text('Does thing 1.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text(l10n.optEmptyPresetAll(6)), findsOneWidget);

    await tester.tap(find.text('Preset 3'));
    await tester.pump();
    expect(picked.single?.id, 3);
    expect(host.sends, isEmpty);
  });

  testWidgets('with no presets the built-in is the tile, and the library is one tap away',
      (tester) async {
    var managed = 0;
    await pump(
      tester,
      AssistantMode.systemPrompt,
      choices: OptimizerPresetChoices(
        presets: const [],
        selectedId: null,
        builtinSelected: true,
        onPick: (_) {},
        onManage: () => managed++,
      ),
    );
    final l10n = await en();

    expect(find.text(l10n.optPresetBuiltinName), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(find.text(l10n.optEmptyPresetCreate));
    expect(managed, 1);
  });

  testWidgets('an example fills the composer and stops there', (tester) async {
    final host = await pump(tester, AssistantMode.knowledgeEdit);
    final l10n = await en();

    await tester.tap(find.text(l10n.optEmptyKbEditExample2));
    await tester.pump();
    expect(host.input.text, l10n.optEmptyKbEditExample2);
    expect(host.sends, isEmpty);
  });

  testWidgets('tiles stack in one column on a phone without overflowing', (tester) async {
    await pump(
      tester,
      AssistantMode.systemPrompt,
      size: const Size(390, 800),
      choices: OptimizerPresetChoices(
        presets: presets,
        selectedId: 1,
        builtinSelected: false,
        onPick: (_) {},
        onShowAll: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    final a = tester.getTopLeft(find.text('Preset 1'));
    final b = tester.getTopLeft(find.text('Preset 2'));
    expect(b.dy, greaterThan(a.dy));
  });
}
