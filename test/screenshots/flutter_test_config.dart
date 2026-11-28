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
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/privacy/ai_consent_service.dart';
import 'package:path/path.dart' as p;

import '../support/fake_async_database_rule.dart';
import '../support/real_fonts.dart';

/// Where the PNGs land. `flutter test` runs with the package root as cwd, and
/// `/build/` is already gitignored.
const String kScreenshotDir = 'build/ui-screenshots';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // FontLoader and rootBundle both need a binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  // MyApp does not set debugShowCheckedModeBanner, so without this every shot
  // carries the DEBUG ribbon across its top-right corner.
  WidgetsApp.debugAllowBannerOverride = false;
  await ensureRealTestFontsLoaded();
  goldenFileComparator = _ScreenshotWriter(Directory(kScreenshotDir));
  // The one thing in this directory that *can* fail a shot: see the rule.
  // Existing protocol fixtures use local/mock transports. Consent behavior has
  // its own isolated tests; never read the user's permission database here.
  AiConsentService.instance = AiConsentService.withStore(
    read: () async => null,
    write: (_) async {},
  )..requestConsent = (_) async => true;
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
