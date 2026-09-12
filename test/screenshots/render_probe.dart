// Render-performance probe — a measuring tool, not a gate.
//
//   flutter test test/screenshots/render_probe.dart
//
// Deliberately NOT named `*_test.dart`: `flutter test` with no arguments
// collects only that pattern, so this stays out of CI, where a few hundred
// lines of measurement would be noise. Name the file and it runs.
//
// What it is for: answering "what does this change actually cost" against the
// real app tree instead of against an argument about it. It mounts the same
// tree the screenshots do (`mountApp`, which exists for exactly this), and
// reports what one state change rebuilds, what a gesture costs end to end,
// and where the glass and the repaint boundaries actually sit.
//
// Reading the numbers:
//
//   * The widget counts are the signal. They come from
//     `debugPrintRebuildDirtyWidgets`, which prints a line per element that
//     rebuilt, and they are what was wrong in every case this probe has been
//     used to find.
//   * The milliseconds are not. A widget test is debug JIT and pumps build →
//     layout → paint with no raster, so the absolute figures run several
//     times a release build's. Compare them to each other, across a change,
//     never to a frame budget.
//   * Fixtures are seeded once per run, so two runs of the same code give the
//     same counts. Screenshots taken across runs do NOT compare pixel for
//     pixel — the fixture's temp path is randomised and scan order can move.
//
// The guards that keep these numbers from regressing live in
// `rebuild_scope_test.dart` and `test/render_performance_test.dart`. This
// file is where you go when you want a figure they do not assert.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:joycai_image_ai_toolkits/models/task_item.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/widgets/app_breathing_dot.dart';

import 'harness/fixture_env.dart';
import 'harness/fixture_seed.dart';
import 'harness/shoot.dart';

const Size _kWindow = Size(1440, 900);

/// How many extra source images to write before the gallery first scans, so
/// the grid is as full as a real library makes it rather than as full as the
/// screenshot fixtures need.
const int _kBulkImages = 120;

void say(String line) => debugPrint(line);

/// The widgets that own a glass layer, for naming one in the report. Anything
/// not on this list is layout or gesture plumbing between the two.
const Set<String> _kGlassOwners = <String>{
  'AppTitleBar',
  'AppTopBar',
  'NavLensGroup',
  'PhoneDock',
  'WorkbenchGlassToolbar',
  'GallerySelectionBar',
  'VideoTabSelectionBar',
  'BrowserSelectionBar',
  'PromptSelectionCapsule',
  'TaskCapsuleMonitor',
  'AppSnackbarHost',
  'AppGlassMenu',
  'CropResizeToolbar',
  'MaskEditorToolbar',
  'PromptOptimizerToolbar',
  'ComparatorToolbar',
  'ImageCard',
  'ModelsPhoneLayout',
};

// ── Measuring ───────────────────────────────────────────────────────────────

/// Every widget `debugPrintRebuildDirtyWidgets` reports for one pump.
Future<List<String>> rebuildsFrom(
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

/// Milliseconds a single build → layout → paint pass takes, averaged. See the
/// header on why this is the weaker of the two figures.
Future<double> costOf(
  WidgetTester tester,
  void Function() change, {
  int runs = 20,
}) async {
  for (int i = 0; i < 3; i++) {
    change();
    await tester.pump();
  }
  final Stopwatch sw = Stopwatch()..start();
  for (int i = 0; i < runs; i++) {
    change();
    await tester.pump();
  }
  sw.stop();
  return sw.elapsedMicroseconds / runs / 1000;
}

/// The widget types that subscribe to [notifier] and rebuilt, with their
/// counts — the roots of a rebuild rather than everything swept up under one.
Map<String, int> dependentsOf(List<String> lines, String notifier) {
  final Map<String, int> counts = <String, int>{};
  for (final String line in lines) {
    if (!line.contains('_InheritedProviderScope<$notifier')) continue;
    final String name = line
        .replaceFirst(RegExp(r'^(Rebuilding|Building)\s+'), '')
        .split(RegExp(r'[(\-]'))
        .first
        .trim();
    if (name.isEmpty || name.startsWith('_InheritedProviderScope')) continue;
    counts[name] = (counts[name] ?? 0) + 1;
  }
  return counts;
}

void reportDependents(List<String> lines, String notifier) {
  final Map<String, int> counts = dependentsOf(lines, notifier);
  if (counts.isEmpty) {
    say('      (nothing subscribed to $notifier rebuilt)');
    return;
  }
  final List<MapEntry<String, int>> sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final MapEntry<String, int> e in sorted) {
    say('      ${e.value.toString().padLeft(3)} × ${e.key}');
  }
}

/// Lets the app's own scheduled work run out.
///
/// Mounting cards schedules metadata reads, and the browser's pulse clears
/// itself on a 1.5s timer; flutter_test fails a test that ends with either
/// still pending, which for a probe is noise about work it never measured.
Future<void> drain(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

// ── Probes ──────────────────────────────────────────────────────────────────

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureEnv env;

  setUpAll(() async {
    env = installFixtureEnv(binding);
    await seedFixtures(env);
    await writeBulkGalleryImages(env, _kBulkImages);
    await writeBulkBrowserFiles(env, _kBulkImages);

    final AppState appState = AppState();
    await appState.loadSettings();
    // Real async: the compute()-based scans only make progress out here.
    await Future<void>.delayed(const Duration(seconds: 2));
    markOneTaskRunning(appState);
  });

  tearDownAll(() => env.dispose());

  testWidgets('workbench — what one gallery change rebuilds',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.workbench,
      size: _kWindow,
      label: 'probe-workbench',
    );
    final gallery = AppState().galleryState;
    final images = gallery.currentViewImages;
    say('\n══ WORKBENCH · ${images.length} images @ ${_kWindow.width.toInt()}×'
        '${_kWindow.height.toInt()} ══');

    // A selection change with one already selected: the ordinary case, and
    // the one the per-card Selector exists for.
    gallery.toggleImageSelection(images.first);
    await tester.pump();
    final List<String> pick =
        await rebuildsFrom(tester, () => gallery.toggleImageSelection(images[1]));
    say('  selection, one card changes   ${pick.length} builds  '
        '${(await costOf(tester, () => gallery.toggleImageSelection(images[1]))).toStringAsFixed(1)} ms');
    reportDependents(pick, 'GalleryState');

    // The empty ↔ non-empty boundary, which the phone layout's FAB turns on.
    gallery.clearImageSelection();
    await tester.pump();
    final List<String> firstPick = await rebuildsFrom(
        tester, () => gallery.toggleImageSelection(images.first));
    say('  selection, empty ↔ not        ${firstPick.length} builds');

    // A whole size drag, one logical pixel at a time, the way a slider
    // reports. The interesting figure is the total: the snapping ladder is
    // what makes most of these free.
    int builds = 0;
    final DebugPrintCallback original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null) builds++;
    };
    debugPrintRebuildDirtyWidgets = true;
    final Stopwatch sw = Stopwatch()..start();
    for (double v = 80; v <= 400; v += 1) {
      gallery.setThumbnailSize(v);
      await tester.pump();
    }
    sw.stop();
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = original;
    say('  size drag 80→400 (321 events) $builds builds  ${sw.elapsedMilliseconds} ms total');

    // What the app's other notifiers cost from here.
    say('  appState.notify()             '
        '${(await costOf(tester, AppState().notify)).toStringAsFixed(1)} ms');
    final queue = AppState().taskQueue;
    say('  queue progress tick           '
        '${(await rebuildsFrom(tester, () => queue.progressTick.value++)).length} builds');
    await drain(tester);
  });

  testWidgets('tasks — what the queue costs as it grows',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.tasks,
      size: _kWindow,
      label: 'probe-tasks',
    );
    final queue = AppState().taskQueue;
    say('\n══ TASKS ══');

    Future<void> line(String label) async {
      final int tick =
          (await rebuildsFrom(tester, () => queue.progressTick.value++)).length;
      final int structural =
          (await rebuildsFrom(tester, queue.refreshQueue)).length;
      final double cost =
          await costOf(tester, () => queue.progressTick.value++);
      say('  ${label.padRight(22)} progress tick $tick builds '
          '(${cost.toStringAsFixed(1)} ms) · structural notify $structural builds');
    }

    await line('${queue.queue.length} tasks');
    _addSynthetic(queue.queue, 143, env);
    queue.refreshQueue();
    await tester.pump();
    await line('${queue.queue.length} tasks');
    _addSynthetic(queue.queue, 350, env);
    queue.refreshQueue();
    await tester.pump();
    await line('${queue.queue.length} tasks');
    say('  (the tick must not grow with the queue; the structural notify must)');
    await drain(tester);
  });

  testWidgets('file browser — what one browser change rebuilds',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.fileBrowser,
      size: _kWindow,
      label: 'probe-browser',
    );
    final browser = AppState().fileBrowserState;
    say('\n══ FILE BROWSER · ${browser.filteredFiles.length} files ══');

    final files = browser.filteredFiles;
    if (files.isNotEmpty) {
      // A base selection, so the run under test is an ordinary add rather
      // than the empty ↔ not boundary.
      browser.toggleSelection(files.first);
      await tester.pump();
      final List<String> pick =
          await rebuildsFrom(tester, () => browser.toggleSelection(files[1]));
      say('  selection, one card changes   ${pick.length} builds  '
          '${(await costOf(tester, () => browser.toggleSelection(files[1]))).toStringAsFixed(1)} ms');
      reportDependents(pick, 'FileBrowserState');

      // Select-all is the worst case the grid has: every visible card's
      // state changes at once.
      browser.clearSelection();
      await tester.pump();
      final List<String> all = await rebuildsFrom(tester, browser.selectAll);
      say('  select all (${files.length} files)         ${all.length} builds');
      browser.clearSelection();
      await tester.pump();
    }

    final List<String> flash =
        await rebuildsFrom(tester, () => browser.flash(browser.sourceDirectories.first));
    say('  folder pulse                  ${flash.length} builds');
    reportDependents(flash, 'FileBrowserState');
    await drain(tester);
  });

  testWidgets('glass — layers per screen, and any that nest',
      (WidgetTester tester) async {
    say('\n══ GLASS ══');
    say('  AppGlass\'s own budget: one full-width bar plus at most three');
    say('  layers visible at once. A nested filter samples an already blurred');
    say('  surface and should not exist at all.');
    for (final AppScreen screen in AppScreen.values) {
      await mountApp(
        tester,
        env: env,
        screen: screen,
        size: _kWindow,
        label: 'probe-glass-${screen.name}',
        before: (WidgetTester t) async {
          // With a selection, so the bars that only exist then are counted.
          final gallery = AppState().galleryState;
          gallery.selectedImages = gallery.currentViewImages.take(1).toList();
        },
      );
      final List<Element> layers = find.byType(BackdropFilter).evaluate().toList();
      int nested = 0;
      final List<String> owners = <String>[];
      for (final Element layer in layers) {
        // Named by the widgets the app itself declares — the layout and
        // gesture plumbing in between says nothing about which layer this is.
        final List<String> chain = <String>[];
        bool under = false;
        layer.visitAncestorElements((Element a) {
          final String name = a.widget.runtimeType.toString();
          if (name == 'BackdropFilter') under = true;
          if (_kGlassOwners.contains(name)) chain.add(name);
          return chain.length < 2;
        });
        if (under) nested++;
        final String owner = chain.isEmpty ? '?' : chain.join('<');
        owners.add(under ? '$owner (NESTED)' : owner);
      }
      say('  ${screen.name.padRight(12)} ${layers.length} layers'
          '${nested > 0 ? ' · $nested NESTED' : ''}  ${owners.join(' · ')}');
      await drain(tester);
    }
  });

  testWidgets('repaint boundaries — what an animation drags with it',
      (WidgetTester tester) async {
    await mountApp(
      tester,
      env: env,
      screen: AppScreen.tasks,
      size: _kWindow,
      label: 'probe-repaint',
    );
    say('\n══ REPAINT SCOPE ══');
    say('  Walking up from each animating render object to the first repaint');
    say('  boundary. Whatever it crosses on the way repaints with it, every');
    say('  frame — a BackdropFilter among them is the expensive case.');

    // The breathing dot is the app's one looping animation (`00 · 1e`), so it
    // is the one whose scope is paid for continuously.
    final Finder animating = find.descendant(
      of: find.byType(AppBreathingDot),
      matching: find.byType(FadeTransition),
    );
    for (final Element e in animating.evaluate()) {
      final List<String> crossed = <String>[];
      String? boundary;
      e.visitAncestorElements((Element a) {
        if (a.renderObject?.isRepaintBoundary ?? false) {
          boundary = a.widget.runtimeType.toString();
          return false;
        }
        final String name = a.widget.runtimeType.toString();
        if (!name.startsWith('_')) crossed.add(name);
        return true;
      });
      say('  breathing dot → crosses [${crossed.take(6).join(', ')}] '
          '→ $boundary');
    }
    await drain(tester);
  });
}

/// Synthetic queue rows, to see whether a cost grows with the queue.
void _addSynthetic(List<TaskItem> queue, int count, FixtureEnv env) {
  final List<String> images = env.fixtureImagePaths.take(3).toList();
  final int from = queue.length;
  for (int i = 0; i < count; i++) {
    queue.add(TaskItem(
      id: 'probe-${from + i}',
      imagePaths: images,
      parameters: const <String, dynamic>{'prompt': 'probe'},
      modelId: 'probe-model',
      modelDbId: 1,
      channelTag: 'CH',
      status: i % 4 == 0 ? TaskStatus.pending : TaskStatus.completed,
      createdAt: DateTime.now().subtract(Duration(minutes: from + i)),
      startTime: DateTime.now().subtract(const Duration(seconds: 20)),
    ));
  }
}
