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
}
