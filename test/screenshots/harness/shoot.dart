// The screenshot helper: mounts the real app at a given size and writes a PNG.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/constants.dart';
import 'package:joycai_image_ai_toolkits/main.dart';
import 'package:joycai_image_ai_toolkits/state/app_state.dart';
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
  /// The theme seed to render under. Defaults to [AppState]'s own, which is
  /// what the app opens with; pass one of [AppConstants.presetThemes] to check
  /// a screen against a different accent. Appears in the filename so two seeds
  /// never overwrite each other's PNG.
  Color? seedColor,
  Locale locale = const Locale('zh'),
  String? suffix,
  Future<void> Function(WidgetTester tester)? before,
  Future<void> Function(WidgetTester tester)? after,
}) async {
  final String seedTag = seedColor == null
      ? ''
      : '_${AppConstants.presetThemes.entries.firstWhere(
            (e) => e.value.toARGB32() == seedColor.toARGB32(),
            orElse: () => MapEntry('seed${seedColor.toARGB32()}', seedColor),
          ).key.toLowerCase()}';
  final String name = '${screen.name}_${size.label}_${brightness.name}'
      '$seedTag${suffix == null ? '' : '_$suffix'}';

  await mountApp(
    tester,
    env: env,
    screen: screen,
    size: size.size,
    brightness: brightness,
    seedColor: seedColor,
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
  Color? seedColor,
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
  if (seedColor != null) appState.themeSeedColor = seedColor;
  appState.locale = locale;
  // Logs accumulate across shots and would make the console strip differ run
  // to run for reasons that have nothing to do with layout.
  appState.logState.clear();
  seedLogs(appState);
  appState.navigateToScreen(screen.index);
  await before?.call(tester);

  // Real async: the screens' initState sqflite queries and the compute()
  // isolates behind the gallery/browser scans only make progress out here.
  await tester.runAsync(() async {
    await tester.pumpWidget(_appTree(appState));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await tester.pump();
    await _warmImageCache(tester, env);
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

Widget _appTree(AppState appState) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider.value(value: appState.taskQueue),
      ChangeNotifierProvider.value(value: appState.workbenchUIState),
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
      await precacheImage(FileImage(File(path)), context);
    } catch (_) {
      // A format the decoder does not handle (the .mp4/.mp3 stubs); the widget
      // shows its own error placeholder, which is what the real app does too.
    }
  }
  try {
    await precacheImage(const AssetImage('assets/icon/icon.png'), context);
  } catch (_) {
    // Only the About block's logo; not worth failing a shot over.
  }
}
