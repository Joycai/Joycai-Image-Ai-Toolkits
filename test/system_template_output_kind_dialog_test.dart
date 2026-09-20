// `A3e 5a / 5b`: the library's template dialog is where a preset's output
// kind is chosen, and the list says so for the ones that answer in the chat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/models/prompt.dart';
import 'package:joycai_image_ai_toolkits/screens/prompts/widgets/prompt_dialogs.dart';
import 'package:joycai_image_ai_toolkits/screens/prompts/widgets/prompt_library_parts.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_neutral_marker.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/private_data_dir.dart';

void main() {
  usePrivateDataDir('joycai_template_output_kind_test');
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppLocalizations l10n;
  // Made here, in real time: the app state opens the database as it is
  // built, and an open begun inside a test's fake-async zone never finishes —
  // every later query, and the process's exit, would wait on it.
  late AppState app;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
    app = AppState();
    await app.getSystemPrompts();
  });

  /// A few frames past the dialog's and the row's animations. Not
  /// `pumpAndSettle`: the editor's caret never stops asking for one.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens the dialog over an empty page.
  Future<void> openDialog(
    WidgetTester tester, {
    SystemPrompt? prompt,
    String defaultType = SystemPrompt.typeRefiner,
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSystemPromptEditDialog(
                  context,
                  l10n,
                  prompt: prompt,
                  systemPrompts: const [],
                  tags: const [],
                  defaultType: defaultType,
                  initialContent: 'BODY',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  /// Saves, then reads the table back — in real time throughout, so the
  /// handler's database calls can finish; a pump per wait lets the dialog
  /// close once they have.
  Future<List<SystemPrompt>> saveAndRead(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      await tester.tap(find.text(l10n.save));
      for (var i = 0; i < 100 && find.text(l10n.save).evaluate().isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(l10n.save), findsNothing, reason: 'the dialog closes once saved');
      return app.getSystemPrompts();
    }))!;
  }

  testWidgets('a new assistant preset defaults to a prompt and says what that means', (tester) async {
    await openDialog(tester);
    expect(find.text(l10n.presetOutput), findsOneWidget);
    expect(find.text(l10n.presetOutputPromptHelp), findsOneWidget);

    await tester.tap(find.text(l10n.presetOutputAnalysis));
    await settle(tester);
    expect(find.text(l10n.presetOutputAnalysisHelp), findsOneWidget);
    expect(find.text(l10n.presetOutputPromptHelp), findsNothing);
  });

  testWidgets('the chosen kind is what gets saved', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'Garment analysis');
    await tester.tap(find.text(l10n.presetOutputAnalysis));
    await settle(tester);

    final rows = await saveAndRead(tester);
    final saved = rows.singleWhere((p) => p.title == 'Garment analysis');
    expect(saved.outputKind, PresetOutputKind.analysis);
  });

  testWidgets('a rename template has no output row, and is saved as a prompt', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'Renamer');
    await tester.tap(find.text(l10n.presetOutputAnalysis));
    await settle(tester);

    await tester.tap(find.text(l10n.typeRename));
    await settle(tester);
    expect(find.text(l10n.presetOutput), findsNothing);

    // Back again: the choice made before the detour is still there.
    await tester.tap(find.text(l10n.typeRefiner));
    await settle(tester);
    expect(find.text(l10n.presetOutputAnalysisHelp), findsOneWidget);

    await tester.tap(find.text(l10n.typeRename));
    await settle(tester);
    final rows = await saveAndRead(tester);
    final saved = rows.singleWhere((p) => p.title == 'Renamer');
    expect(saved.type, SystemPrompt.typeRename);
    expect(saved.outputKind, PresetOutputKind.prompt);
  });

  testWidgets('editing opens on the kind the preset has', (tester) async {
    await openDialog(
      tester,
      prompt: SystemPrompt(
        id: 1,
        title: 't',
        content: 'c',
        type: SystemPrompt.typeRefiner,
        outputKind: PresetOutputKind.analysis,
      ),
    );
    expect(find.text(l10n.presetOutputAnalysisHelp), findsOneWidget);
  });

  testWidgets('the dialog fits a phone', (tester) async {
    await openDialog(tester, size: const Size(390, 800));
    expect(tester.takeException(), isNull, reason: 'both type labels share the row');
    await tester.tap(find.text(l10n.presetOutputAnalysis));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only an analysis preset wears the marker in the list', (tester) async {
    Future<void> pump(PresetOutputKind kind) => tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: PromptTemplateTypeBadge(type: SystemPrompt.typeRefiner, outputKind: kind),
            ),
          ),
        ));

    await pump(PresetOutputKind.prompt);
    await tester.pump();
    expect(find.byType(AppNeutralMarker), findsNothing);

    await pump(PresetOutputKind.analysis);
    await tester.pump();
    expect(find.byType(AppNeutralMarker), findsOneWidget);
    expect(find.text(l10n.presetOutputAnalysis), findsOneWidget);
    expect(find.text(l10n.typeRefiner), findsOneWidget);
  });
}
