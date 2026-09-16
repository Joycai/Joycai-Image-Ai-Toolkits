import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/ai_rename_dialog.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/ai_rename_agent.dart';
import 'package:joycai_image_ai_toolkits/services/tasks/ai_rename_review.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/state/file_browser_state.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'screenshots/harness/fixture_env.dart';
import 'screenshots/harness/fixture_seed.dart';

/// The review list's 「覆盖」 on a clash. Two rows proposing one name have no
/// file to overwrite — only each other's result — so the action is drawn but
/// unavailable, and says why. `resolveRenameConflict` refuses it as well
/// (`ai_rename_review_test.dart`); this is the half a person sees.
void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;
  late Directory dir;

  // Seeded: without a chat model the dialog shows its 「no model」 state in
  // place of the review list.
  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    await AppState().loadSettings();
  });
  tearDownAll(() => env.dispose());

  setUp(() {
    dir = Directory.systemTemp.createTempSync('joycai_ai_rename_ui');
    for (final name in ['a.png', 'b.png', 'c.png', 'taken.png']) {
      File(p.join(dir.path, name)).writeAsStringSync(name);
    }
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Left for the OS cleaner.
    }
  });

  RenameReviewRow row(String from, String to) => RenameReviewRow(RenameProposal(
        path: p.join(dir.path, from),
        oldName: from,
        newName: to,
      ));

  Future<void> pumpDialog(WidgetTester tester, List<RenameReviewRow> rows) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final appState = AppState();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: appState),
          ChangeNotifierProvider<FileBrowserState>.value(value: appState.fileBrowserState),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: AiRenameDialog(debugInitialRows: rows)),
        ),
      ),
    );
    await tester.pump();
  }

  // Labelled or folded to a glyph, depending on how much room the row has.
  Finder overwrite() => find.byWidgetPredicate((w) =>
      (w is IconButton && (w.tooltip ?? '').startsWith('Overwrite')) ||
      (w is ButtonStyleButton &&
          find
              .descendant(of: find.byWidget(w), matching: find.text('Overwrite'))
              .evaluate()
              .isNotEmpty));

  VoidCallback? onPressedOf(Widget w) =>
      w is IconButton ? w.onPressed : (w as ButtonStyleButton).onPressed;

  testWidgets('a clash between two rows offers Overwrite disabled, with the reason',
      (tester) async {
    final rows = [row('a.png', 'same.png'), row('b.png', 'same.png')];
    await tester.runAsync(() => recomputeRenameConflicts(rows));
    expect(rows.map((r) => r.conflict), everyElement(RenameConflict.duplicate));

    await pumpDialog(tester, rows);

    final buttons = overwrite();
    expect(buttons, findsNWidgets(2));
    for (final element in buttons.evaluate()) {
      expect(onPressedOf(element.widget), isNull,
          reason: 'Overwrite must not be tappable on a row-vs-row clash');
    }
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.byWidgetPredicate((w) =>
          (w is Tooltip && (w.message ?? '').contains(l10n.renameOverwriteDuplicateHint)) ||
          (w is IconButton && (w.tooltip ?? '').contains(l10n.renameOverwriteDuplicateHint))),
      findsWidgets,
      reason: 'a disabled Overwrite has to say why',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a clash with a file on disk keeps Overwrite available', (tester) async {
    final rows = [row('c.png', 'taken.png')];
    await tester.runAsync(() => recomputeRenameConflicts(rows));
    expect(rows.single.conflict, RenameConflict.targetExists);

    await pumpDialog(tester, rows);

    final buttons = overwrite();
    expect(buttons, findsOneWidget);
    expect(onPressedOf(tester.widget(buttons)), isNotNull);
  });
}
