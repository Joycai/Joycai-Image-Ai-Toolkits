import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/core/app_theme.dart';
import 'package:path/path.dart' as p;

Future<void>? _loading;

/// Registers the real UI, mono, and icon fonts in `flutter_test` once per isolate.
///
/// Without this, `flutter_test` draws every glyph as an Ahem 1em square box,
/// skewing text wrapping and overflow measurements. Calling this is idempotent
/// and safe for non-screenshot layout and contrast tests that want real metrics.
Future<void> ensureRealTestFontsLoaded() {
  TestWidgetsFlutterBinding.ensureInitialized();
  return _loading ??= _loadFonts();
}

Future<void> _loadFonts() async {
  // NotoSansSC first, and it is the one that matters: it covers Latin *and*
  // CJK, which is why a missing SDK Roboto degrades gracefully rather than
  // ruining the shot. The app downloads it at runtime (FontService) rather
  // than bundling it, so the harness keeps its own copy next to screenshots —
  // byte-identical to what the download fetches.
  final List<ByteData> noto = _loadFromFiles(<String>[
    'test/screenshots/fonts/NotoSansSC-Regular.ttf',
    'test/screenshots/fonts/NotoSansSC-Bold.ttf',
  ]);
  await _register('NotoSansSC', noto);

  // Families the app names but that never resolve inside flutter_test: alias
  // them all to NotoSansSC for legible metrics.
  if (noto.isNotEmpty) {
    for (final String alias in <String>[
      'HarmonyOSSansSC',
      'MiSans',
      'PingFang SC',
      'Microsoft YaHei',
    ]) {
      await _register(alias, <ByteData>[noto.first]);
    }
  }

  // Register every name in the mono stack so fallback through CJK reaches the
  // UI font instead of boxing on an unregistered family name.
  final List<ByteData> mono = _loadFromFiles(<String>[
    'test/screenshots/fonts/CascadiaMono-Regular.ttf',
    'test/screenshots/fonts/CascadiaMono-SemiBold.ttf',
  ]);
  for (final String family in kMonoFontFamilyFallback) {
    await _register(family, mono);
  }

  // Icons: `uses-material-design: true` puts this in the asset bundle. Fall
  // back to the SDK cache if the bundle lookup fails.
  final List<ByteData> icons = await _loadFromBundle(<String>['fonts/MaterialIcons-Regular.otf']);
  await _register(
    'MaterialIcons',
    icons.isNotEmpty ? icons : _loadFromSdk(<String>['MaterialIcons-Regular.otf']),
  );

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
    debugPrint(
      '[test_fonts] font family "$family" unavailable — '
      'text using it will render as boxes',
    );
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
    ?Platform.environment['FLUTTER_ROOT'],
    ..._ancestorsOf(Platform.resolvedExecutable),
  ];
  for (final String root in roots) {
    final String dir = p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts');
    if (Directory(dir).existsSync()) return dir;
  }
  debugPrint(
    '[test_fonts] could not locate the Flutter SDK material_fonts '
    'directory; falling back to bundled fonts only',
  );
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
