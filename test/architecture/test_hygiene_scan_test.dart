import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prevents test assertions (`expect(...)`) from being buried inside files
/// tagged `@Tags(['screenshots'])`, which CI skips via `-x screenshots`.
///
/// Screenshot harness files use `expectLater(..., matchesGoldenFile(...))` to
/// render PNGs, never `expect(...)` to verify behavior. Behavior assertions
/// belong in un-tagged tests under `test/app/`, `test/widgets/`, or
/// `test/screens/`.
void main() {
  final lineComment = RegExp(r'(^|\s)//.*$');
  final screenshotsTag = RegExp(r'''@Tags\([^)]*['"]screenshots['"]''');
  final bareExpect = RegExp(r'\bexpect\s*\(');

  test('screenshot-tagged files contain no skipped expect() assertions', () {
    final offenders = <String>[];
    final dir = Directory('test/screenshots');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
      final source = entity.readAsStringSync();
      if (!screenshotsTag.hasMatch(source)) continue;

      final lines = source.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final code = lines[i].replaceFirst(lineComment, '');
        if (bareExpect.hasMatch(code)) {
          final path = entity.path.replaceAll(r'\', '/');
          offenders.add('$path:${i + 1}  ${code.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Found expect() inside @Tags([\'screenshots\']) files (which CI skips '
          'with `-x screenshots`). Move these assertions to normal widget tests:\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}
