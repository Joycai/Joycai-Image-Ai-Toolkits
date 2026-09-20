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

import 'package:joycai_image_ai_toolkits/core/text_editing_focus.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/directory_tree_item.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';
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
    await settle(tester);

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
}
