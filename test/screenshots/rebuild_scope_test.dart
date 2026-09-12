// What a change in one notifier is allowed to rebuild.
//
//   flutter test test/screenshots/rebuild_scope_test.dart
//
// Lives beside the screenshot harness because it needs the same real app
// tree and the same fixtures — a rebuild count taken against a different
// mount than the one the app actually builds is worth nothing.
//
// These assert on *which widgets* rebuild, never on a frame time: a clock in
// a widget test is a flake generator, and the count is the thing that was
// actually wrong.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';

/// Every widget `debugPrintRebuildDirtyWidgets` reports for one pump.
Future<List<String>> rebuiltBy(
  WidgetTester tester,
  void Function() change,
) async {
  final List<String> lines = <String>[];
  final DebugPrintCallback original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  debugPrintRebuildDirtyWidgets = true;
  change();
  await tester.pump();
  debugPrintRebuildDirtyWidgets = false;
  debugPrint = original;
  return lines;
}

Matcher rebuilt(String name) => contains(contains(name));

/// How many widgets of one type the pump rebuilt.
int timesRebuilt(List<String> lines, String name) =>
    lines.where((String line) => line.contains(name)).length;

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    final AppState appState = AppState();
    await appState.loadSettings();
    await Future<void>.delayed(const Duration(seconds: 1));
    markOneTaskRunning(appState);
  });

  tearDownAll(() => env.dispose());

  testWidgets('picking a picture rebuilds the selection, not the workbench',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'rebuild-scope-workbench',
    );

    // The glass budget, on the screen that carries the most of it. AppGlass's
    // own doc allows one full-width bar plus three floating layers; the
    // workbench had seven, three of them lenses re-blurring the bar or the
    // toolbar they sat on.
    expect(find.byType(BackdropFilter), findsNWidgets(4));

    final gallery = AppState().galleryState;
    final images = gallery.currentViewImages;
    expect(images, isNotEmpty, reason: 'the fixture gallery must have tiles');

    // Start from one selected, so the run under test does not also cross the
    // empty/non-empty boundary — that boundary legitimately moves the phone
    // layout's FAB, and is covered below.
    gallery.toggleImageSelection(images.first);
    await tester.pump();

    final List<String> lines =
        await rebuiltBy(tester, () => gallery.toggleImageSelection(images[1]));

    // What must rebuild: the bar that counts the selection.
    expect(lines, rebuilt('GallerySelectionBar'));

    // What must not. Each of these subscribed to the whole GalleryState for
    // one narrow fact, so a selection change rebuilt the entire folder tree,
    // the toolbar and both glass shells with it.
    expect(lines, isNot(rebuilt('FolderList')),
        reason: 'the folder column draws no part of the selection');
    expect(lines, isNot(rebuilt('DirectoryTreeItem')),
        reason: 'a tree row needs the refresh tick, not the whole notifier');
    expect(lines, isNot(rebuilt('ResultTreeItem')),
        reason: 'a tree row needs the refresh tick, not the whole notifier');
    expect(lines, isNot(rebuilt('WorkbenchGlassToolbar')),
        reason: 'the toolbar shows which view is current, not what is picked');
    expect(lines, isNot(rebuilt('WorkbenchScreen')),
        reason: 'on a desktop window the FAB that reads the selection is not '
            'even drawn — the screen must not subscribe to it');
  });

  testWidgets('dragging the size slider does not rebuild the chrome',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'rebuild-scope-slider',
    );

    final gallery = AppState().galleryState;
    gallery.setThumbnailSize(160);
    await tester.pump();

    // One step of the slider's ladder — see snapThumbnailSize.
    final List<String> lines =
        await rebuiltBy(tester, () => gallery.setThumbnailSize(168));

    expect(lines, isNot(rebuilt('FolderList')));
    expect(lines, isNot(rebuilt('GallerySelectionBar')));
    expect(lines, isNot(rebuilt('DirectoryTreeItem')));

    // And a move inside one step reaches nothing at all.
    final List<String> none =
        await rebuiltBy(tester, () => gallery.setThumbnailSize(170));
    expect(none, isEmpty,
        reason: 'a slider position the layout cannot distinguish from the '
            'last one must not reach the widget tree');
  });

  testWidgets('a progress tick reaches the running card, not the task screen',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.tasks,
      size: const Size(1440, 900),
      label: 'rebuild-scope-tasks',
    );

    final queue = AppState().taskQueue;
    expect(
      queue.queue.where((t) => t.status == TaskStatus.processing),
      isNotEmpty,
      reason: 'the fixture must have a running task for the tick to mean '
          'anything',
    );

    // The 500ms estimate moving. It reaches the running card's progress edge
    // and the console strip's percentage — and stops there.
    final List<String> tick =
        await rebuiltBy(tester, () => queue.progressTick.value++);
    expect(tick, isNot(rebuilt('TaskQueueScreen')),
        reason: 'the filter, the sort and the queue-position pass must not '
            'run twice a second');
    expect(tick, isNot(rebuilt('_GroupDivider')));

    // The queue's *shape* changing is a different matter: that is what the
    // screen draws, and it must still rebuild for it.
    final List<String> structural =
        await rebuiltBy(tester, queue.refreshQueue);
    expect(structural, rebuilt('TaskQueueScreen'));
    expect(structural.length, greaterThan(tick.length * 3),
        reason: 'if the two notifications cost the same, the split has been '
            'undone somewhere');
  });

  testWidgets('registering a folder does reach the folder column',
      (WidgetTester tester) async {
    // The other half of narrowing a subscription: a selector that compares a
    // list by identity only fires if the state hands back a *new* list. The
    // class documents that it always does; these two paths did not, and
    // narrowing FolderList onto `sourceDirectories` would have quietly
    // stopped the column from showing a folder the user had just added.
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: const Size(1440, 900),
      label: 'rebuild-scope-add-folder',
    );

    final gallery = AppState().galleryState;
    final String added = env.docsDir.path;
    expect(gallery.sourceDirectories, isNot(contains(added)));

    // Registering writes to the database before it notifies, and only
    // `runAsync` lets that finish — so the change is made out here and the
    // rebuild it leaves behind is captured on the next pump.
    await tester.runAsync(() => gallery.addBaseDirectory(added));
    final List<String> lines = await rebuiltBy(tester, () {});
    expect(gallery.sourceDirectories, contains(added));
    expect(lines, rebuilt('FolderList'),
        reason: 'the column lists the source folders — it must rebuild when '
            'one is registered');

    await tester.runAsync(() => gallery.removeBaseDirectory(added));
    final List<String> removal = await rebuiltBy(tester, () {});
    expect(removal, rebuilt('FolderList'),
        reason: 'and when one is taken off the list');
  });

  testWidgets('a folder pulse reaches one tree row, not the browser',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: const Size(1440, 900),
      label: 'rebuild-scope-browser',
    );

    final browser = AppState().fileBrowserState;
    expect(browser.sourceDirectories, isNotEmpty);

    // The pulse names at most one row. It used to go out through
    // notifyListeners — twice, once to set and once to clear 1.5s later — so
    // the file grid, the filter bar and every other row rebuilt for a cue
    // none of them draw.
    final List<String> pulse =
        await rebuiltBy(tester, () => browser.flash(browser.sourceDirectories.first));
    expect(pulse, rebuilt('DirectoryTreeItem'));
    expect(pulse, isNot(rebuilt('FileBrowserScreen')));
    expect(pulse, isNot(rebuilt('FolderList')));
    expect(pulse, isNot(rebuilt('FileCard')));

    // And a selection change, which the column has no part in either.
    final files = browser.filteredFiles;
    expect(files.length, greaterThan(4), reason: 'need a grid, not one row');

    // From one already picked, so this is an ordinary add rather than the
    // empty ↔ not boundary.
    browser.toggleSelection(files.first);
    await tester.pump();
    final List<String> pick =
        await rebuiltBy(tester, () => browser.toggleSelection(files[1]));

    expect(pick, isNot(rebuilt('FolderList')));
    expect(pick, isNot(rebuilt('DirectoryTreeItem')));
    // The grid is where this cost sat: the screen watched the whole notifier,
    // so picking one file rebuilt the header, the filter bar, the tree and
    // every visible tile. Each tile carries its own subscription now.
    expect(pick, isNot(rebuilt('FileBrowserScreen')),
        reason: 'the layout draws no part of the selection');
    expect(pick, isNot(rebuilt('_FileArea')),
        reason: 'the area draws the file list, not what is picked');
    expect(pick, isNot(rebuilt('BrowserFilterBar')));
    // The header states the count, so one line of it has to move — but only
    // that line. Rebuilding the header took the search field, the staging
    // button, the view toggle and the refresh button with it, and re-ran the
    // width measurement that decides whether the header collapses.
    expect(pick, rebuilt('_HeaderSummary'),
        reason: 'the subtitle states how many files are picked');
    expect(pick, isNot(rebuilt('BrowserHeader')),
        reason: 'and nothing else in the header does');
    expect(
      timesRebuilt(pick, 'FileCard('),
      lessThanOrEqualTo(2),
      reason: 'one tile changed — at most it and the one that lost the '
          'anchor may rebuild, never the whole grid',
    );
    browser.clearSelection();
    await tester.pump();

    // Let the pulse's own 1.5s clear timer run out before the tree is torn
    // down; flutter_test fails a test that ends with one pending.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  });
}
