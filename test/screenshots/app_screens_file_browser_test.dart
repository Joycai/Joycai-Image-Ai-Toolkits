// Screenshots of the file browser and the downloader: the screen matrix, the
// staging area, the conflict pass, folder management and the AI rename
// dialog. See docs/ui-screenshot-harness.md.
//
//   flutter test test/screenshots
//   flutter test test/screenshots/app_screens_file_browser_test.dart

@Tags(<String>['screenshots'])
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/models/browser_file.dart';
import 'package:joycai_image_ai_toolkits/screens/browser/widgets/file_card.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/directory_tree_item.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/glass/app_glass_menu.dart';
import 'package:path/path.dart' as p;

import 'harness/fixture_env.dart';
import 'harness/shoot.dart';
import 'harness/suite.dart';

void main() {
  late FixtureEnv env;
  setUpScreenSuite((FixtureEnv e) => env = e);

  shootMatrix(() => env, const <AppScreen>[AppScreen.fileBrowser, AppScreen.downloader]);

  // The staging area only exists once something is in it, and the matrix
  // photographs the browser with an empty one — which is the one state of this
  // feature that shows none of it. `12a` is the frame being implemented here,
  // so it gets its own shot with the panel populated, a destination named, a
  // selection live (floating bar) and a mark that has gone stale.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · staging @ desktop ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'staging',
        before: (WidgetTester tester) async {
          final AppState appState = AppState();
          final browser = appState.fileBrowserState;
          final staging = appState.fileStagingState;

          staging.clear();
          staging.addAll(browser.filteredFiles.take(5));
          // A mark whose file is gone — the panel has to keep showing it.
          staging.addAll(<BrowserFile>[
            BrowserFile(
              path: p.join(env.browserDir.path, 'deleted_by_someone_else.png'),
              name: 'deleted_by_someone_else.png',
              category: FileCategory.image,
              size: 0,
              modified: DateTime(2026, 8, 1),
            ),
          ]);
          // `runAsync`, not a bare await: `before` runs inside the test's
          // fake-async zone, where a real `File.stat()` never completes and the
          // await hangs the shot forever.
          await tester.runAsync(() => staging.revalidate());
          staging.setDestination(env.browserDir.path);

          browser.clearSelection();
          for (final BrowserFile f in browser.filteredFiles.skip(4).take(3)) {
            browser.toggleSelection(f);
          }
        },
      );
    });
  }

  // `B1a 12c` — the panel with nothing in it. The matrix photographs the
  // browser with an empty staging area, but the panel only opens itself once
  // something is staged, so the state that has to explain the feature was the
  // one state never rendered.
  testWidgets('fileBrowser · stagingEmpty @ desktop light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: kShotSizes.last,
      suffix: 'stagingEmpty',
      before: (WidgetTester tester) async {
        final AppState appState = AppState();
        appState.fileStagingState.clear();
        appState.fileStagingState.setDestination(null);
        appState.fileBrowserState.clearSelection();
      },
      after: (WidgetTester tester) async {
        await tester.tap(find.byTooltip('暂存区').first);
        for (int i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      },
    );
  });

  // `B1a 12e` — the conflict pass. Needs a real name collision on disk, so the
  // fixture grows a subfolder holding a file the staged one would land on.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · conflicts @ desktop ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'conflicts',
        before: (WidgetTester tester) async {
          final AppState appState = AppState();
          final browser = appState.fileBrowserState;
          final staging = appState.fileStagingState;

          final Directory dest =
              Directory(p.join(env.browserDir.path, 'archive'));
          // Real files, written through runAsync: `before` runs in the
          // fake-async zone where dart:io never completes.
          await tester.runAsync(() async {
            if (!await dest.exists()) await dest.create();
            for (final BrowserFile f in browser.filteredFiles.take(3)) {
              await File(p.join(dest.path, f.name)).writeAsString('older copy');
            }
          });

          staging.clear();
          staging.addAll(browser.filteredFiles.take(3));
          staging.setDestination(dest.path);
          browser.clearSelection();
        },
        after: (WidgetTester tester) async {
          await tester.runAsync(() async {
            await tester.tap(find.text('移动到此'));
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 500));
          });
          for (int i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        },
      );
    });
  }

  // `B1b 13a/13b/13d` — the folder management the tree grew: the root's
  // context menu (with its "remove from list" / disabled "move to…" rules),
  // the in-row name field for a new subfolder, and the delete confirmation
  // for a subfolder that has something in it.
  Future<void> ensureArchive(WidgetTester tester) => tester.runAsync(() async {
        final Directory dest = Directory(p.join(env.browserDir.path, 'archive'));
        if (!await dest.exists()) await dest.create();
        await File(p.join(dest.path, 'kept.txt')).writeAsString('kept');
      });

  // The folder name also appears in the staging panel's group header when
  // an earlier shot left marks behind, so the row is found through the tree.
  Finder treeRow(String name) => find.descendant(
        of: find.byType(DirectoryTreeItem),
        matching: find.text(name),
      );

  Finder menuItem(String label) => find.descendant(
        of: find.byType(AppGlassMenu),
        matching: find.text(label),
      );

  testWidgets('fileBrowser · folderMenu @ desktop light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: kShotSizes.last,
      suffix: 'folderMenu',
      before: ensureArchive,
      after: (WidgetTester tester) async {
        await tester.tap(treeRow('browser').first, buttons: kSecondaryButton);
        await settle(tester);
      },
    );
  });

  // The file rename dialog (`A1 · 2b`): float-grade glass at r22 over the
  // lighter scrim, the stem selected, the extension locked beside it. Opened
  // from a file card's menu, which is how both the browser and the gallery
  // reach it.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · fileRename @ desktop ${brightness.name}', (WidgetTester tester) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'fileRename',
        after: (WidgetTester tester) async {
          await tester.tap(find.byType(FileCard).first, buttons: kSecondaryButton);
          await settle(tester);
          await tester.tap(menuItem('重命名'));
          await settle(tester);
        },
      );
    });
  }

  testWidgets('fileBrowser · folderNew @ desktop light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: kShotSizes.last,
      suffix: 'folderNew',
      before: ensureArchive,
      after: (WidgetTester tester) async {
        await tester.tap(treeRow('browser').first, buttons: kSecondaryButton);
        await settle(tester);
        // The subfolder listing behind the editor is real dart:io.
        await tester.runAsync(() async {
          await tester.tap(menuItem('新建子文件夹'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await settle(tester);
      },
    );
  });

  testWidgets('fileBrowser · folderDelete @ desktop light', (WidgetTester tester) async {
    await shoot(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: kShotSizes.last,
      suffix: 'folderDelete',
      before: ensureArchive,
      after: (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.tap(find.descendant(
            of: find.byType(DirectoryTreeItem),
            matching: find.byIcon(Icons.chevron_right),
          ));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await settle(tester);
        await tester.tap(treeRow('archive').first, buttons: kSecondaryButton);
        await settle(tester);
        // The inventory runs in a compute isolate; the dialog opens first and
        // fills its counts when that lands.
        await tester.runAsync(() async {
          await tester.tap(menuItem('删除'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 800));
        });
        await settle(tester);
      },
    );
  });

  // The AI rename dialog — `B4 13a`. Its result states need a live model, so
  // only the opened-but-not-generated frame is reachable here; that still
  // covers the shell, the config column, the result toolbar, the empty state
  // and the footer, which is where the redraw's shape lives.
  for (final Brightness brightness in Brightness.values) {
    testWidgets('fileBrowser · aiRename @ desktop ${brightness.name}', (
      WidgetTester tester,
    ) async {
      await shoot(
        tester,
        env: env,
        screen: AppScreen.fileBrowser,
        size: kShotSizes.last,
        brightness: brightness,
        suffix: 'aiRename',
        before: (WidgetTester tester) async {
          final AppState appState = AppState();
          appState.fileStagingState.clear();
          final browser = appState.fileBrowserState;
          browser.clearSelection();
          for (final BrowserFile f in browser.filteredFiles.take(6)) {
            browser.toggleSelection(f);
          }
        },
        after: (WidgetTester tester) async {
          // Tap and wait inside `runAsync`: the dialog reads its templates and
          // its last-used model out of the database on mount, and that real
          // I/O never completes in the fake-async zone. Without it the shot
          // photographs an empty config column and calls it the design.
          await tester.runAsync(() async {
            await tester.tap(find.text('AI 批量重命名').last);
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 600));
          });
          for (int i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
        },
      );
    });
  }
}
