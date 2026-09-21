// The screenshot helper: mounts the real app at a given size and writes a PNG.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/main.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
import 'package:joycai_image_ai_toolkits/core/theme_accent.dart';
import 'package:provider/provider.dart';

import 'fixture_env.dart';
import 'fixture_seed.dart';

/// Declared in the order of `_getNavDefinitions` in main.dart:239-248, so
/// `AppScreen.index` *is* the argument `AppState.navigateToScreen` wants.
///
/// The mapping is 1:1 only because the harness runs on a desktop host: at
/// main.dart:256 `isMobilePlatform` reads `Platform.isAndroid || isIOS`, so it
/// is always false here and no destinations are filtered out. See the caveat
/// in docs/ui-screenshot-harness.md about the 390px shots.
enum AppScreen {
  workbench,
  fileBrowser,
  tasks,
  downloader,
  prompts,
  models,
  usage,
  settings,
}

class ShotSize {
  const ShotSize(this.label, this.size);
  final String label;
  final Size size;
}

const List<ShotSize> kShotSizes = <ShotSize>[
  ShotSize('mobile', Size(390, 844)), //   < 600  → NavigationBar + drawer
  ShotSize('tablet', Size(834, 1112)), //  < 1000 → icon-only rail
  // iPad landscape. Its own band because the screen is just over the desktop
  // breakpoint while the content box — the window minus the 78px rail — is
  // just under it, and nothing else here lands in that gap. The workbench
  // squeezing its centre panel to 152px lived in exactly this 20px-wide band
  // of window widths for as long as the harness skipped it.
  ShotSize('ipad', Size(1024, 768)), //    ≥ 1000 screen, < 1000 content
  ShotSize('desktop', Size(1440, 900)), // ≥ 1000 → labelled rail
];

/// Renders [screen] at [size] and writes `<screen>_<size>_<brightness><suffix>.png`
/// into `build/ui-screenshots/`.
///
/// [before] runs after the singleton is configured but before the first pump —
/// use it to set state the screen reads on mount. [after] runs on the settled
/// tree, for taps that open a dialog or switch a tab.
Future<void> shoot(
  WidgetTester tester, {
  required FixtureEnv env,
  required AppScreen screen,
  required ShotSize size,
  Brightness brightness = Brightness.light,
  /// The theme colour to render under. Defaults to [AppState]'s own, which is
  /// what the app opens with; pass one of [AppConstants.presetThemes] to check
  /// a screen against a different accent. Appears in the filename so two
  /// accents never overwrite each other's PNG.
  ThemeAccent? accent,
  Locale locale = const Locale('zh'),
  String? suffix,
  Future<void> Function(WidgetTester tester)? before,
  Future<void> Function(WidgetTester tester)? after,
}) async {
  final String seedTag = accent == null
      ? ''
      : '_${AppConstants.presetThemes.entries.firstWhere(
            (e) => e.value == accent,
            orElse: () => MapEntry('seed${accent.light.toARGB32()}', accent),
          ).key.toLowerCase()}';
  final String name = '${screen.name}_${size.label}_${brightness.name}'
      '$seedTag${suffix == null ? '' : '_$suffix'}';

  await mountApp(
    tester,
    env: env,
    screen: screen,
    size: size.size,
    brightness: brightness,
    accent: accent,
    locale: locale,
    label: name,
    before: before,
    after: after,
  );

  await expectLater(find.byType(MyApp), matchesGoldenFile('$name.png'));
}

/// Mounts the real app at [size] on [screen] and settles it.
///
/// Split out of [shoot] so tests that need to *measure* the app rather than
/// photograph it get the same tree, the same fixtures and the same settling —
/// a layout assertion is worth nothing if it runs against a subtly different
/// mount than the screenshots do.
Future<void> mountApp(
  WidgetTester tester, {
  required FixtureEnv env,
  required AppScreen screen,
  required Size size,
  Brightness brightness = Brightness.light,
  ThemeAccent? accent,
  Locale locale = const Locale('zh'),
  String label = 'mount',
  Future<void> Function(WidgetTester tester)? before,
  Future<void> Function(WidgetTester tester)? after,
}) async {
  final String name = label;

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final AppState appState = AppState();
  appState.themeMode =
      brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  if (accent != null) appState.themeAccent = accent;
  appState.locale = locale;
  // Logs accumulate across shots and would make the console strip differ run
  // to run for reasons that have nothing to do with layout.
  appState.logState.clear();
  seedLogs(appState);
  appState.navigateToScreen(screen.index);
  await before?.call(tester);

  // Twice: on the way out, so a test that never mounts through here (one that
  // calls `precacheImage` itself) does not inherit this one's loads, and on the
  // way in, for a file whose earlier test left some without going through here.
  addTearDown(dropUnfinishedImageLoads);
  dropUnfinishedImageLoads();

  // Real async: the screens' initState sqflite queries and the compute()
  // isolates behind the gallery/browser scans only make progress out here.
  //
  // [stalled] carries a failed warm-up out by hand. What a `runAsync` body
  // throws is parked where `takeException` finds it, and that slot holds one:
  // an overflow from the first pump would already be in it, and the drain at
  // the bottom of this function prints whatever it finds and moves on.
  WarmUpStalled? stalled;
  await tester.runAsync(() async {
    await tester.pumpWidget(_appTree(appState));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tester.pump();
    try {
      await _warmImageCache(tester, env);
    } on WarmUpStalled catch (e) {
      stalled = e;
      return;
    }
    await tester.pump();
    // A second settle, for the loads that only *start* once the first round's
    // results are on screen. The assistant's knowledge tree is the case that
    // needed it: the screen reads the configured folder, hands the path down,
    // and only then does the panel walk it — a chain whose second half is
    // scheduled inside this block and would otherwise be left pending when it
    // ends, since the fake-async pumps below cannot complete a real-async
    // future. Kept short — it is waiting for a couple of event-loop turns and
    // a folder walk, not for the database — because it is paid once per shot
    // across ~180 of them.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  });
  if (stalled case final WarmUpStalled e) throw e;

  // 800ms covers every AppMotion duration used across the screens (the
  // ladder tops out at AppMotion.panel, 300ms).
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  if (after != null) {
    await after(tester);
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Drain, never assert. An overflow is the bug we are hunting, and
  // expect(takeException(), isNull) would abort before writing the PNG —
  // losing exactly the picture worth looking at.
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    debugPrint('[$name] exception during pump: $e');
  }

  await tester.pump();
}

/// Forgets every image load that has not finished.
///
/// The image cache outlives a test, and so does a load that was still pending
/// when the test ended. One started by a pump outside `runAsync` lives in that
/// test's fake-async zone, which is gone: it never completes, and the next
/// `precacheImage` for the same path is handed the same completer and waits on
/// it for good. `render_probe.dart`'s thumbnail-size drag leaves ~180 behind.
///
/// `putIfAbsent` hands a completer back from either of two maps. The pending
/// one is only emptied by `clear()`, which takes the decoded entries with it —
/// so only when there is something pending. The live one is pure bookkeeping
/// and costs nothing to drop, and must go every time: a `clear()` from anywhere
/// else empties the pending map and leaves the dead completer in this one.
void dropUnfinishedImageLoads() {
  if (imageCache.pendingImageCount > 0) imageCache.clear();
  imageCache.clearLiveImages();
}

Widget _appTree(AppState appState) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider.value(value: appState.taskQueue),
      ChangeNotifierProvider.value(value: appState.workbenchUIState),
      ChangeNotifierProvider.value(value: appState.taskListState),
      ChangeNotifierProvider.value(value: appState.modelListState),
      ChangeNotifierProvider.value(value: appState.fileBrowserState),
      ChangeNotifierProvider.value(value: appState.fileStagingState),
      // main.dart does not register this one, but several widgets read it.
      ChangeNotifierProvider.value(value: appState.galleryState),
      ChangeNotifierProvider.value(value: appState.downloaderState),
      ChangeNotifierProvider.value(value: appState.logState),
    ],
    child: const MyApp(version: '3.13.0'),
  );
}

/// [_warmImageCache] gave up on [path].
class WarmUpStalled implements Exception {
  WarmUpStalled(this.path)
      : pending = imageCache.pendingImageCount,
        live = imageCache.liveImageCount;

  final String path;
  final int pending;
  final int live;

  @override
  String toString() => 'warm-up never finished for $path — an image load left '
      'over from an earlier test? pending=$pending live=$live';
}

/// Real time: the warm-up runs inside `runAsync`, where timers are real.
const Duration _kWarmLimit = Duration(seconds: 10);

/// One image into the cache, or [WarmUpStalled].
///
/// A timeout here is not a slow decode — these are fixture PNGs. It is a load
/// the cache handed back that can no longer finish (see
/// [dropUnfinishedImageLoads]). Left unbounded it does not fail a test, it
/// hangs the process: nothing after it runs, and CI sits until the job's own
/// timeout with no name and no path to show for it.
Future<void> _warm(ImageProvider image, BuildContext context, String path) =>
    precacheImage(image, context).timeout(
      _kWarmLimit,
      onTimeout: () => throw WarmUpStalled(path),
    );

/// Decoding a [FileImage] is asynchronous, so without this every thumbnail
/// captures as an empty box — the classic golden-test failure.
///
/// Must run after the gallery scan: `GalleryState._evictImages` clears the
/// image cache on every scan, which would undo the warm-up.
Future<void> _warmImageCache(WidgetTester tester, FixtureEnv env) async {
  final Finder app = find.byType(MyApp);
  if (app.evaluate().isEmpty) return;
  final BuildContext context = tester.element(app);

  for (final String path in env.fixtureImagePaths) {
    try {
      await _warm(FileImage(File(path)), context, path);
    } on WarmUpStalled {
      rethrow;
    } catch (_) {
      // A format the decoder does not handle (the .mp4/.mp3 stubs); the widget
      // shows its own error placeholder, which is what the real app does too.
    }
  }
  try {
    await _warm(const AssetImage('assets/icon/icon.png'), context, 'assets/icon/icon.png');
  } on WarmUpStalled {
    rethrow;
  } catch (_) {
    // Only the About block's logo; not worth failing a shot over.
  }
}
