// Test configuration for the UI screenshot harness.
//
// ⚠️ THIS FILE MUST STAY IN `test/screenshots/`. flutter_tools discovers
// `flutter_test_config.dart` by walking up from the test file's own directory
// and taking the FIRST hit. Moving this to `test/` would apply it to all of the
// other test files, changing their text metrics — several of them assert on
// layout and overflow, so they would start failing for no real reason.
//
// It does two things:
//   1. Loads real fonts. Without this, flutter_test's default font draws every
//      glyph as a filled box and the screenshots are worthless.
//   2. Installs a golden comparator that always overwrites and never fails, so
//      these are a debugging tool rather than a pixel-diff regression gate.
//   3. Installs the suite-wide rule against database calls under fake async
//      (`test/support/fake_async_database_rule.dart`) — this directory's
//      config shadows `test/`'s, so it has to be installed here as well.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/fake_async_database_rule.dart';

/// Where the PNGs land. `flutter test` runs with the package root as cwd, and
/// `/build/` is already gitignored.
const String kScreenshotDir = 'build/ui-screenshots';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // FontLoader and rootBundle both need a binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  // MyApp does not set debugShowCheckedModeBanner, so without this every shot
  // carries the DEBUG ribbon across its top-right corner.
  WidgetsApp.debugAllowBannerOverride = false;
  await _loadFonts();
  goldenFileComparator = _ScreenshotWriter(Directory(kScreenshotDir));
  // The one thing in this directory that *can* fail a shot: see the rule.
  installFakeAsyncDatabaseRule();
  await testMain();
}

/// Writes every capture to disk and always passes.
///
/// The stock [LocalFileComparator] turns `matchesGoldenFile` into a pixel-diff
/// gate that fails on any UI change — exactly wrong for a tool whose whole job
/// is to show what the UI currently looks like. Overriding [compare] to write
/// also means no `--update-goldens` flag and lets the output live in `build/`
/// instead of next to the test file.
class _ScreenshotWriter extends GoldenFileComparator {
  _ScreenshotWriter(this.outputDir);

  final Directory outputDir;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    await update(golden, imageBytes);
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final File file = File(p.join(outputDir.path, golden.pathSegments.last));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(imageBytes, flush: true);
    debugPrint('screenshot → ${file.absolute.path}');
  }
}

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

Future<void> _loadFonts() async {
  // NotoSansSC first, and it is the one that matters: it covers Latin *and*
  // CJK, which is why a missing SDK Roboto degrades gracefully rather than
  // ruining the shot. The app downloads it at runtime (FontService) rather
  // than bundling it, so the harness keeps its own copy next to this file —
  // byte-identical to what the download fetches.
  final List<ByteData> noto = _loadFromFiles(<String>[
    'test/screenshots/fonts/NotoSansSC-Regular.ttf',
    'test/screenshots/fonts/NotoSansSC-Bold.ttf',
  ]);
  await _register('NotoSansSC', noto);

  // Families the app names but that never resolve inside flutter_test: the
  // nav rail task badge asks for 'monospace' (main.dart:637), the settings
  // font picker previews each option in its own family, and
  // FontService.systemFontFamily — what AppState's default 'system' choice
  // feeds ThemeData, so nearly all app text — is whatever the OS provides.
  // Their labels would photograph as boxes and read as a broken harness.
  // Alias them all to NotoSansSC — the point is legibility, not typographic
  // accuracy.
  if (noto.isNotEmpty) {
    for (final String alias in <String>[
      'monospace',
      'HarmonyOSSansSC',
      'MiSans',
      'PingFang SC',
      'Microsoft YaHei',
    ]) {
      await _register(alias, <ByteData>[noto.first]);
    }
  }

  // Icons: `uses-material-design: true` puts this in the asset bundle. Fall
  // back to the SDK cache if the bundle lookup fails.
  final List<ByteData> icons =
      await _loadFromBundle(<String>['fonts/MaterialIcons-Regular.otf']);
  await _register(
    'MaterialIcons',
    icons.isNotEmpty ? icons : _loadFromSdk(<String>['MaterialIcons-Regular.otf']),
  );

  // Roboto is only reached by text that names no family, so it is the least
  // important of the three.
  await _register(
    'Roboto',
    _loadFromSdk(<String>[
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
      'Roboto-Italic.ttf',
    ]),
  );
}

Future<void> _register(String family, List<ByteData> data) async {
  if (data.isEmpty) {
    debugPrint('[screenshots] font family "$family" unavailable — '
        'text using it will render as boxes');
    return;
  }
  final FontLoader loader = FontLoader(family);
  for (final ByteData bytes in data) {
    loader.addFont(Future<ByteData>.value(bytes));
  }
  await loader.load();
}

Future<List<ByteData>> _loadFromBundle(List<String> keys) async {
  final List<ByteData> out = <ByteData>[];
  for (final String key in keys) {
    try {
      out.add(await rootBundle.load(key));
    } catch (_) {
      // Missing from the bundle; the caller decides whether that is fatal.
    }
  }
  return out;
}

/// Reads [paths] relative to the package root (`flutter test`'s cwd).
List<ByteData> _loadFromFiles(List<String> paths) {
  final List<ByteData> out = <ByteData>[];
  for (final String path in paths) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    out.add(ByteData.sublistView(file.readAsBytesSync()));
  }
  return out;
}

List<ByteData> _loadFromSdk(List<String> fileNames) {
  final String? dir = _materialFontsDir();
  if (dir == null) return const <ByteData>[];
  final List<ByteData> out = <ByteData>[];
  for (final String name in fileNames) {
    final File file = File(p.join(dir, name));
    if (!file.existsSync()) continue;
    final Uint8List bytes = file.readAsBytesSync();
    out.add(ByteData.sublistView(bytes));
  }
  return out;
}

/// Locates `<flutter>/bin/cache/artifacts/material_fonts`, never hardcoded.
String? _materialFontsDir() {
  final List<String> roots = <String>[
    // `flutter test` exports this (bin/internal/shared.sh).
    ?Platform.environment['FLUTTER_ROOT'],
    // Otherwise walk up from <flutter>/bin/cache/dart-sdk/bin/dart.
    ..._ancestorsOf(Platform.resolvedExecutable),
  ];
  for (final String root in roots) {
    final String dir = p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts');
    if (Directory(dir).existsSync()) return dir;
  }
  debugPrint('[screenshots] could not locate the Flutter SDK material_fonts '
      'directory; falling back to bundled fonts only');
  return null;
}

Iterable<String> _ancestorsOf(String path) sync* {
  String dir = p.dirname(path);
  for (int i = 0; i < 6; i++) {
    yield dir;
    final String parent = p.dirname(dir);
    if (parent == dir) return;
    dir = parent;
  }
}
