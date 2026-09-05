import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Points `path_provider` at a temp directory belonging to this test file
/// alone, and returns it.
///
/// `flutter test` runs test *files* concurrently, each in its own isolate, but
/// they all share one filesystem. A file that answers the path_provider
/// channel with the shared `Directory.systemTemp.path` therefore names the
/// same `joycai_workbench.db` as every other file that does — and since
/// `DatabaseService` is a singleton over a real file, a query that lands while
/// a neighbouring file holds the write lock dies with
/// `SqfliteFfiException(sqlite_error: 5, database is locked)`. The race is
/// invisible per file (nothing to race against) and only shows up in a full
/// suite run, which makes it read as a flake rather than as shared state.
///
/// Call this from `main()`'s body — not from `setUpAll`, which runs too late
/// to register the `tearDownAll` that removes the directory — and before
/// anything constructs `DatabaseService`, `AppState`, or a state class that
/// loads its settings while constructing.
///
/// One directory answers every path_provider method. Tests that need the data,
/// temp and documents directories to stay distinct want the screenshot
/// harness's `installFixtureEnv` instead.
Directory usePrivateDataDir(String prefix) {
  final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized();
  final Directory dir = Directory.systemTemp.createTempSync(prefix);

  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async => dir.path,
  );

  tearDownAll(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // The sqflite handle may still be open; the OS reaps temp dirs anyway.
    }
  });

  return dir;
}
