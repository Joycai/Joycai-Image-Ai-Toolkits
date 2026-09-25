import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The UI layer does not open the database. A screen or widget gets its data
/// from a state's cached field, a state method, a screen controller whose
/// database was injected, or a service — never by constructing
/// `DatabaseService()` or an `XxxRepository()` of its own.
///
/// Fourteen files used to. Two of the writes never reached the state that
/// cached the same rows (the setup wizard's channel and model, invisible until
/// a restart), and none of them could be handed `openTestDatabase()`. This is
/// a source scan, like `panel_width_keys_scan_test.dart`, because
/// `source_layout_test.dart` sees only imports and `screens/` may import
/// `services/` freely; what it guards is the *expression*.
///
/// The one allowed spelling is the injection default — `database ??
/// DatabaseService()` on a controller's constructor, as `UsageController`
/// has — which is what the `??` exemption below is for.
void main() {
  final constructs = RegExp(r'\b(DatabaseService(\.\w+)?|[A-Z]\w*Repository)\s*\(');
  // `<parameter> ?? ` right before it: a named identifier, so `null ??` and
  // an expression do not pass.
  final injectionDefault = RegExp(r'\b(?!null\b)[a-z]\w*\s*\?\?\s*$');

  test('screens and widgets construct no DatabaseService or repository', () {
    final offenders = <String>[];
    for (final dir in ['lib/screens', 'lib/widgets']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final path = f.path.replaceAll(r'\', '/');
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          for (final m in constructs.allMatches(line)) {
            if (injectionDefault.hasMatch(line.substring(0, m.start))) continue;
            offenders.add('$path:${i + 1}  ${line.trim()}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'the UI layer takes its data from a state field, a state method, an injected '
          'controller or a service (CLAUDE.md, "Take the database, don\'t fetch it"):\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}
