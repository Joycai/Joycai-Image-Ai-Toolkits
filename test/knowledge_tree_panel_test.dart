// `A2 10h`'s left column.
//
// The thing worth pinning is the merge: a file the agent has proposed
// *creating* is not on disk, so the folder walk cannot see it — and that is
// exactly the row whose badge the column exists for. Without the merge the
// tree quietly omits half of what is about to change.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/l10n/app_localizations.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/widgets/knowledge_tree_panel.dart';
import 'package:joycai_image_ai_toolkits/services/prompt_optimizer_agent.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('kb_panel_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // The OS reaps systemTemp regardless.
    }
  });

  void writeFile(String relPath) {
    final file = File(p.join(root.path, relPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('# rule');
  }

  Future<AppLocalizations> en() => AppLocalizations.delegate.load(const Locale('en'));

  Future<void> pumpTree(
    WidgetTester tester, {
    List<OptimizerChatEntry> pending = const [],
    String? path,
  }) async {
    tester.view.physicalSize = const Size(300, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: KnowledgeTreePanel(kbPath: path ?? root.path, pendingKbEdits: pending),
      ),
    ));
    // The walk is deliberately off the build path — a zero-duration timer, so
    // the clock has to move before anything can be asserted about the rows.
    // Fixed pumps rather than pumpAndSettle: a scan in flight draws a
    // CircularProgressIndicator, which never settles.
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// A staged edit, built the way the agent builds one.
  OptimizerChatEntry edit(String path, {String? oldContent}) =>
      OptimizerChatEntry(
        kind: OptimizerEntryKind.kbEdit,
        text: path,
        editId: 'e_$path',
        targetPath: path,
        newContent: '# new',
        oldContent: oldContent,
        editState: KbEditState.pending,
      );

  /// Row labels in the order they are drawn.
  List<String> rowsOf(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();

  testWidgets('a folder with a staged edit inside it starts open', (tester) async {
    writeFile('01_rules/01a_light.md');
    writeFile('07_shoes/07b_socks.md');

    await pumpTree(tester, pending: [edit('07_shoes/07b_socks.md', oldContent: '# old')]);

    // The one with something waiting is expanded; the other is not.
    expect(find.text('07b_socks.md'), findsOneWidget);
    expect(find.text('01a_light.md'), findsNothing);
  });

  testWidgets('a proposed new file appears even though it is not on disk', (tester) async {
    writeFile('04_templates/04_cosplay.md');

    await pumpTree(tester, pending: [edit('04_templates/04b_id_photo.md')]);

    expect(find.text('04b_id_photo.md'), findsOneWidget);
    final l10n = await en();
    expect(find.text(l10n.optKbTreeAdded), findsOneWidget);
  });

  testWidgets('the new file lands among its siblings, not at the end', (tester) async {
    writeFile('04_templates/04_cosplay.md');
    writeFile('04_templates/04c_portrait.md');
    writeFile('09_negatives.md');

    await pumpTree(tester, pending: [edit('04_templates/04b_id_photo.md')]);

    final rows = rowsOf(tester);
    final cosplay = rows.indexOf('04_cosplay.md');
    final idPhoto = rows.indexOf('04b_id_photo.md');
    final portrait = rows.indexOf('04c_portrait.md');
    final negatives = rows.indexOf('09_negatives.md');

    expect(cosplay, greaterThanOrEqualTo(0));
    expect(idPhoto, greaterThan(cosplay));
    expect(portrait, greaterThan(idPhoto));
    // And inside the folder rather than after everything under the root.
    expect(negatives, greaterThan(portrait));
  });

  testWidgets('a proposed file in a folder that does not exist brings the folder', (tester) async {
    writeFile('README.md');

    await pumpTree(tester, pending: [edit('11_new_area/11a_first.md')]);

    expect(find.text('11_new_area'), findsOneWidget);
    expect(find.text('11a_first.md'), findsOneWidget);
  });

  testWidgets('the header count includes what is only proposed', (tester) async {
    writeFile('README.md');
    final l10n = await en();

    await pumpTree(tester);
    expect(find.text(l10n.optKbDocCount(1)), findsOneWidget);

    await pumpTree(tester, pending: [edit('new.md')]);
    expect(find.text(l10n.optKbDocCount(2)), findsOneWidget);
  });

  testWidgets('the footer counts what is waiting on the user', (tester) async {
    writeFile('a.md');
    writeFile('b.md');
    final l10n = await en();

    await pumpTree(tester, pending: [
      edit('a.md', oldContent: '# old'),
      edit('c.md'),
    ]);
    expect(find.text(l10n.optKbTreePending(2)), findsOneWidget);
  });

  testWidgets('nothing staged means no footer at all', (tester) async {
    writeFile('a.md');
    await pumpTree(tester);
    final l10n = await en();
    expect(find.text(l10n.optKbTreePending(0)), findsNothing);
  });

  testWidgets('an unconfigured base says so rather than showing an empty tree', (tester) async {
    await pumpTree(tester, path: '');
    final l10n = await en();
    expect(find.text(l10n.optKbNotConfigured), findsOneWidget);
  });
}
