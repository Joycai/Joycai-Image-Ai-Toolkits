// Which keys the file browser is allowed to claim.
//
//   flutter test test/screenshots/browser_shortcut_scope_test.dart
//
// Lives beside the screenshot harness because it needs the same real app
// tree — the thing under test is what a key does after travelling up through
// the screen's actual focus chain, which no stand-in can reproduce.
//
// Asserts, so it stays in the gate (like rebuild_scope_test.dart) and is not
// tagged `screenshots`.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:joycai_image_ai_toolkits/core/text_editing_focus.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/file_card.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/browser_staging_panel.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/directory_tree_item.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/unified_sidebar.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';
import 'package:joycai_image_ai_toolkits/widgets/dialogs/file_rename_dialog.dart';
import 'package:joycai_image_ai_toolkits/widgets/ui/app_dialog.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    await AppState().loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
  });

  tearDownAll(() => env.dispose());

  testWidgets('the tree\'s rename field keeps the keys the grid would take', (
    WidgetTester tester,
  ) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'browser-shortcut-scope',
    );

    final browser = AppState().fileBrowserState;
    browser.clearSelection();
    for (final BrowserFile f in browser.filteredFiles.take(3)) {
      browser.toggleSelection(f);
    }
    await settle(tester);
    expect(browser.selectedFiles, hasLength(3));

    // Start the inline folder rename the tree offers, which is where this
    // goes wrong: its focus node handles Escape and hands everything else
    // upward, and the next handler in line is the screen's.
    await tester.tap(
      find.descendant(of: find.byType(DirectoryTreeItem), matching: find.text('browser')),
      buttons: kSecondaryButton,
    );
    await settle(tester);
    await tester.tap(
      find.descendant(of: find.byType(AppGlassMenu), matching: find.text('重命名')),
    );
    await settle(tester);

    final Finder field = find.descendant(
      of: find.byType(DirectoryTreeItem),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget, reason: 'the rename field must be open');
    expect(isTextEditingFocused(), isTrue, reason: 'and it must hold the keyboard');

    // Every key the screen claims for the selection, while the field is live.
    final LogicalKeyboardKey mod =
        Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester, 12);

    // Cmd+A must not have reached `selectAll`, and no key may have opened
    // anything: the delete confirmation, the file rename dialog and the media
    // preview would each take the keyboard away from the field, so the focus
    // assertion catches all three at once.
    expect(browser.selectedFiles, hasLength(3),
        reason: 'Cmd+A belongs to the name being typed, not to the grid');
    expect(find.byType(AppDialog), findsNothing);
    expect(field, findsOneWidget, reason: 'the rename field is still open');
    expect(isTextEditingFocused(), isTrue, reason: 'and still has the keyboard');

    // Escape is the editor's own, and closes it — proof the field was live
    // the whole time rather than quietly gone.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(field, findsNothing);
    expect(browser.selectedFiles, hasLength(3),
        reason: 'the editor consumed Escape, so the selection survives it too');
  });

  /// The primary modifier this host spells: the shortcut table resolves it
  /// from `Platform.isMacOS`, so a test must ask the same question.
  final LogicalKeyboardKey primary =
      Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;

  /// [real] sends the chord through `runAsync`, for the handlers that persist
  /// a setting: `saveSetting` starts sqflite's ten-second lock watchdog, and
  /// under fake async that write never finishes, so the timer is still
  /// pending when the test ends — which fails the test on something other
  /// than its subject.
  Future<void> pressChord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
    bool real = false,
  }) async {
    Future<void> send() async {
      await tester.sendKeyDownEvent(primary);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(primary);
    }

    if (real) {
      await tester.runAsync(() async {
        await send();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
    } else {
      await send();
    }
    await settle(tester);
  }

  /// Click a folder in the tree, then a file in the grid — the sequence the
  /// audit caught. See [_clickFolderThenFile].
  Future<void> clickFolderThenFile(WidgetTester tester) async {
    // `FileBrowserState` is a singleton and outlives a mount, so a selection
    // left by an earlier test would make the card tap deselect instead.
    AppState().fileBrowserState.clearSelection();
    await settle(tester);

    await tester.tap(find.descendant(
        of: find.byType(DirectoryTreeItem), matching: find.text('browser')));
    await settle(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'directory-tree-row',
        reason: 'clicking a folder row does put the keyboard on it');

    await tester.tap(find.byType(FileCard).first);
    await settle(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'browser-pane-grid',
        reason: 'and clicking the grid has to take it back — before this '
            'round the grid was not focusable at all, so the tree row kept '
            'the keyboard until something else happened to take it');
    expect(AppState().fileBrowserState.selectedFiles, hasLength(1));
  }

  testWidgets('Delete after clicking a folder deletes the files, not the folder',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'browser-pane-delete',
    );
    await clickFolderThenFile(tester);
    final BrowserFile picked = AppState().fileBrowserState.selectedFiles.single;

    // `runFileDelete` asks the filesystem whether a trash exists before it
    // can word the confirmation, and that answer only arrives out here —
    // fake-async pumps cannot complete it.
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester, 12);

    // The defect, as an assertion: this used to open 「移除文件夹？」 for the
    // folder clicked a moment earlier, while the selected files sat
    // untouched.
    expect(find.text('移除文件夹？'), findsNothing,
        reason: 'Delete belongs to the pane that has the keyboard, and that '
            'is the grid');
    expect(find.byType(AppDialog), findsOneWidget,
        reason: 'the file delete confirmation is what should have opened');
    // …and it is about the selected file, not about anything else: the
    // confirmation lists what it is going to delete.
    expect(
        find.descendant(
            of: find.byType(AppDialog), matching: find.text(picked.name)),
        findsOneWidget,
        reason: 'the dialog must name the file that was selected');
  });

  testWidgets('F2 after clicking a folder renames the file, not the folder',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'browser-pane-rename',
    );
    await clickFolderThenFile(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await settle(tester);

    expect(
        find.descendant(
            of: find.byType(DirectoryTreeItem), matching: find.byType(TextField)),
        findsNothing,
        reason: 'F2 used to open the tree\'s inline folder-name editor');
    expect(find.byType(FileRenameDialog), findsOneWidget,
        reason: 'the file rename dialog is what should have opened');
  });

  testWidgets('Cmd+F during an inline rename does not commit the half-typed name',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'browser-gate-order',
    );

    await tester.tap(
      find.descendant(of: find.byType(DirectoryTreeItem), matching: find.text('browser')),
      buttons: kSecondaryButton,
    );
    await settle(tester);
    await tester.tap(
      find.descendant(of: find.byType(AppGlassMenu), matching: find.text('重命名')),
    );
    await settle(tester);

    final Finder field = find.descendant(
      of: find.byType(DirectoryTreeItem),
      matching: find.byType(TextField),
    );
    expect(field, findsOneWidget);

    await tester.enterText(field, 'half-typed');
    await settle(tester);

    // The screen used to claim Cmd+F *above* the text-editing gate, so focus
    // jumped to the search box and the editor, which commits on blur
    // (`folder_name_editor._onFocusChange`), wrote whatever was in it.
    final LogicalKeyboardKey mod =
        Platform.isMacOS ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(mod);
    await settle(tester);

    expect(field, findsOneWidget, reason: 'the editor must still be open');
    expect(isTextEditingFocused(), isTrue,
        reason: 'and still hold the keyboard — no *key* may pull focus out of '
            'a live editor, because leaving it is what commits. A click in '
            'another pane still does, deliberately: that is the rule '
            'FolderNameEditor documents.');
    // `FolderOperationsService.rename` writes to `dirname(path)/newName`, and
    // the row being renamed is the registered root `<root>/browser` — so the
    // half-typed name would land beside it, not inside it. (It landed inside
    // it in the first draft of this test, which made the assertion unfailable
    // and the disk check worthless.)
    expect(Directory(p.join(env.root.path, 'half-typed')).existsSync(), isFalse,
        reason: 'and the half-typed name must not have reached the disk');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(field, findsNothing);
  });

  testWidgets('Cmd+\\ hides and shows the folder column', (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'browser-toggle-folders',
    );
    addTearDown(() => AppState().setSidebarExpanded(true));

    expect(find.byType(UnifiedSidebar), findsOneWidget);

    await pressChord(tester, LogicalKeyboardKey.backslash, real: true);
    expect(find.byType(UnifiedSidebar), findsNothing,
        reason: 'the column is gone');
    // And there is a way back that is not the keyboard: a column you can only
    // restore with a shortcut you have to already know is a trap.
    expect(find.byIcon(Icons.menu), findsOneWidget);

    await pressChord(tester, LogicalKeyboardKey.backslash, real: true);
    expect(find.byType(UnifiedSidebar), findsOneWidget);
    expect(find.byIcon(Icons.menu_open), findsOneWidget);
  });

  testWidgets('Shift+Cmd+\\ opens and closes the staging column',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'browser-toggle-staging',
    );

    final bool openAtStart = find.byType(BrowserStagingPanel).evaluate().isNotEmpty;
    // Asserted, not merely observed: the state classes are singletons shared
    // by every test in this file, so a later test that stages a file would
    // otherwise turn this into a silent check of the opposite transition.
    expect(openAtStart, isFalse,
        reason: 'the fixture stages nothing and the column starts closed');

    await pressChord(tester, LogicalKeyboardKey.backslash, shift: true);
    expect(find.byType(BrowserStagingPanel),
        openAtStart ? findsNothing : findsOneWidget);

    await pressChord(tester, LogicalKeyboardKey.backslash, shift: true);
    expect(find.byType(BrowserStagingPanel),
        openAtStart ? findsOneWidget : findsNothing,
        reason: 'the same chord puts it back');
  });

  testWidgets('Shift+Cmd+C copies every selected name, one per line',
      (WidgetTester tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'browser-copy-names',
    );

    final browser = AppState().fileBrowserState;
    browser.clearSelection();
    for (final BrowserFile f in browser.filteredFiles.take(2)) {
      browser.toggleSelection(f);
    }
    await settle(tester);
    // The grid pane is autofocused, so the keys work without a click.
    await pressChord(tester, LogicalKeyboardKey.keyC, shift: true);

    expect(copied, browser.selectedFiles.map((f) => f.name).join('\n'));
    expect(copied, contains('\n'), reason: 'two files, two lines');
  });
}
