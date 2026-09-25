// `A3d 4e`: in maintenance the documents take the left column, and the
// reference images — still sent with every message — stay one tap away.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/assistant/knowledge_tree_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/assistant/optimizer_left_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/assistant/optimizer_reference_panel.dart';
import 'package:joycai_image_ai_toolkits/services/assistant/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/workbench_ui_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_segmented_control.dart';
import 'package:provider/provider.dart';
import '../../../support/private_data_dir.dart';
import '../../../support/real_async.dart';

void main() {
  usePrivateDataDir('joycai_optimizer_left_panel_test');
  useRealAsyncAppState();

  Future<void> pump(WidgetTester tester, AssistantMode mode) async {
    final ui = WorkbenchUIState()..optimizerSession = PromptOptimizerSession(mode: mode);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: AppState()),
          ChangeNotifierProvider<WorkbenchUIState>.value(value: ui),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SizedBox(width: 250, child: OptimizerLeftPanel(kbPath: null))),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('outside maintenance there is no switch, only the references', (tester) async {
    for (final mode in [AssistantMode.systemPrompt, AssistantMode.knowledgeBase]) {
      await pump(tester, mode);
      expect(find.byType(AppSegmentedControl<bool>), findsNothing, reason: mode.name);
      expect(find.byType(OptimizerReferencePanel), findsOneWidget, reason: mode.name);
    }
  });

  testWidgets('maintenance opens on the documents and can show the references', (tester) async {
    await pump(tester, AssistantMode.knowledgeEdit);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(find.byType(KnowledgeTreePanel), findsOneWidget);
    // Not even built until asked for: its panel follows every session
    // notification, which an unseen copy would pay for.
    expect(find.byType(OptimizerReferencePanel, skipOffstage: false), findsNothing);

    await tester.tap(find.text(l10n.optLeftRefs(0)));
    await tester.pumpAndSettle();
    expect(find.byType(OptimizerReferencePanel), findsOneWidget);
    expect(find.byType(KnowledgeTreePanel), findsNothing);
    // Still mounted: the tree keeps its open folders and its search.
    expect(find.byType(KnowledgeTreePanel, skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
