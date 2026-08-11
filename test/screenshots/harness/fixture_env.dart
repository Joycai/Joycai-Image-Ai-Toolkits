// Isolated filesystem + plugin environment for the screenshot harness.
//
// Everything here must run BEFORE the first `AppState()` call. `AppState` is a
// hard singleton (app_state.dart:34-35) whose GalleryState / FileBrowserState /
// TaskQueueService fields each fire an async DB read from their constructors —
// so by the time you can await anything, the database path is already chosen.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The temp directory tree every fixture writes into.
class FixtureEnv {
  FixtureEnv._(this.root)
      : dataDir = Directory(p.join(root.path, 'data')),
        tempDir = Directory(p.join(root.path, 'temp')),
        docsDir = Directory(p.join(root.path, 'docs')),
        sourceDir = Directory(p.join(root.path, 'source')),
        outputDir = Directory(p.join(root.path, 'output')),
        browserDir = Directory(p.join(root.path, 'browser'));

  final Directory root;

  /// `getApplicationSupportDirectory` — where `joycai_workbench.db` lands.
  final Directory dataDir;

  /// `getTemporaryDirectory`. GalleryState derives `<temp>/result_cache` from
  /// this and scans it, so fixtures dropped there populate the processed view.
  final Directory tempDir;

  /// `getApplicationDocumentsDirectory`.
  final Directory docsDir;

  /// Workbench source folder, registered as a source directory.
  final Directory sourceDir;

  /// Workbench output folder.
  final Directory outputDir;

  /// File-browser root.
  final Directory browserDir;

  /// `<temp>/result_cache`, the processed-image view's scan root.
  Directory get resultCacheDir => Directory(p.join(tempDir.path, 'result_cache'));

  /// Every image file written by the seeder, for `precacheImage` warm-up.
  final List<String> fixtureImagePaths = <String>[];

  void dispose() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // The sqflite handle may still be open; the OS reaps systemTemp anyway.
    }
  }
}

/// Creates the temp tree and redirects sqflite, path_provider and the plugins
/// that fire during `build` at it.
FixtureEnv installFixtureEnv(TestWidgetsFlutterBinding binding) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // A directory of this harness's own. Point path_provider at the shared
  // systemTemp and every test file opens the same database — `flutter test`
  // runs files concurrently, so they race for its lock and whoever does the
  // most I/O loses with "database is locked".
  final FixtureEnv env = FixtureEnv._(
    Directory.systemTemp.createTempSync('joycai_ui_shots'),
  );
  for (final Directory dir in <Directory>[
    env.dataDir,
    env.tempDir,
    env.docsDir,
    env.sourceDir,
    env.outputDir,
    env.browserDir,
    env.resultCacheDir,
  ]) {
    dir.createSync(recursive: true);
  }

  // In `flutter test` no plugin registers, so PathProviderPlatform.instance
  // stays the package's default MethodChannelPathProvider and this mock is what
  // actually answers. Dispatch per method — the directories must stay distinct
  // or the result-cache scan collides with the database.
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      switch (call.method) {
        case 'getTemporaryDirectory':
          return env.tempDir.path;
        case 'getApplicationDocumentsDirectory':
          return env.docsDir.path;
        case 'getApplicationSupportDirectory':
        case 'getApplicationCachePath':
        case 'getLibraryDirectory':
        default:
          return env.dataDir.path;
      }
    },
  );

  // The About section calls PackageInfo.fromPlatform() from initState; without
  // this the Settings shot carries a MissingPluginException and a blank version.
  PackageInfo.setMockInitialValues(
    appName: 'Joycai Image AI Toolkits',
    packageName: 'com.joycai.imageAiToolkits',
    version: '3.13.0',
    buildNumber: '1',
    buildSignature: '',
  );

  // Mounted by the workbench gallery and the video config panel.
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('desktop_drop'),
    (MethodCall call) async => null,
  );
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('joycai/window_chrome'),
    (MethodCall call) async => null,
  );

  return env;
}
