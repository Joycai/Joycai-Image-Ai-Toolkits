import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/optimizer_config_panel.dart';
import 'package:joycai_image_ai_toolkits/services/knowledge_base_service.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_segmented_control.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The initialize button is a one-shot, destructive-adjacent action: it writes
/// files into a folder the user picked. Its guard is what stops it running over
/// an existing knowledge base, so these pin that the guard is visible in the UI
/// and that the button cannot be fired when the base already has an entry file.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dbDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbDir = Directory.systemTemp.createTempSync('joycai_kb_init_btn_test');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => dbDir.path,
    );
  });

  tearDownAll(() {
    try {
      dbDir.deleteSync(recursive: true);
    } on FileSystemException {
      // The database handle may still be open; the OS reaps temp dirs anyway.
    }
  });

  Future<void> pumpPanel(
    WidgetTester tester,
    KbStatus status, {
    Size size = const Size(1400, 1000),
    Future<void> Function()? onScaffold,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final appState = await tester.runAsync(() async {
      final state = AppState();
      await state.refreshDataCache();
      return state;
    });

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: appState!,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: OptimizerConfigPanel(
            selectedModelDbId: null,
            selectedTagId: null,
            selectedSysPrompt: null,
            useCustomSysPrompt: false,
            mode: AssistantMode.knowledgeBase,
            kbStatus: status,
            kbPath: '/tmp/kb',
            tags: const [],
            filteredSysPrompts: const [],
            onModelChanged: (_) {},
            onTagChanged: (_) {},
            onSysPromptChanged: (_) {},
            onUseCustomChanged: (_) {},
            onModeChanged: (_) {},
            onScaffoldKb: onScaffold ?? () async {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<AppLocalizations> en() => AppLocalizations.delegate.load(const Locale('en'));

  testWidgets('the button is disabled once the base has an entry file', (tester) async {
    await pumpPanel(tester, KbStatus.ok);
    final l10n = await en();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l10n.kbScaffoldCreate),
    );
    // A null callback is what actually makes it inert — not just greyed out.
    expect(button.onPressed, isNull);
  });

  testWidgets('tapping it at ok does nothing', (tester) async {
    var calls = 0;
    await pumpPanel(tester, KbStatus.ok, onScaffold: () async => calls++);
    final l10n = await en();

    await tester.tap(
      find.widgetWithText(FilledButton, l10n.kbScaffoldCreate),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(calls, 0, reason: 'a disabled button must not reach the handler');
  });

  testWidgets('it explains why it is unavailable', (tester) async {
    await pumpPanel(tester, KbStatus.ok);
    final l10n = await en();

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(
      tooltip.message,
      l10n.kbScaffoldAlreadyInit(KnowledgeBaseService.entryFileName),
    );
    expect(tooltip.message, contains('README.md'));
  });

  for (final status in [KbStatus.notSet, KbStatus.missingDir, KbStatus.missingEntry]) {
    testWidgets('the button is live at ${status.name}', (tester) async {
      await pumpPanel(tester, status);
      final l10n = await en();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.kbScaffoldCreate),
      );
      expect(button.onPressed, isNotNull);
    });
  }

  testWidgets('tapping it at missingEntry runs it exactly once', (tester) async {
    var calls = 0;
    await pumpPanel(tester, KbStatus.missingEntry, onScaffold: () async => calls++);
    final l10n = await en();

    await tester.tap(find.widgetWithText(FilledButton, l10n.kbScaffoldCreate));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('all three modes are offered and fit on Mobile', (tester) async {
    await pumpPanel(tester, KbStatus.ok, size: const Size(360, 800));
    final l10n = await en();

    // Scoped to the control: "Knowledge Base" is also the status block's
    // header, so a bare text finder matches twice.
    final selector = find.byType(AppSegmentedControl<AssistantMode>);
    for (final label in [
      l10n.optModeSystemPrompt,
      l10n.optModeKnowledge,
      l10n.optModeKnowledgeEdit,
    ]) {
      expect(
        find.descendant(of: selector, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // Three segments are narrow at 360px; they must ellipsize, never overflow.
    expect(tester.takeException(), isNull);
  });
}
