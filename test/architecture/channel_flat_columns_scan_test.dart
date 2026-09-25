import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A channel's flat `type` / `endpoint` are its *primary* route (standard 02
/// §2). Anything asking a protocol question about a model must go through
/// the model's route (`RoutedChannel.forModel`) or the primary view
/// (`RoutedChannel.primary`); reading the columns straight answers for the
/// primary route after the model moved to another one — silently.
///
/// The readers below are the ones that *should* see the raw columns: the
/// resolver that turns them into routes, the repository that normalizes
/// them, and the channel editor seeding its own form.
void main() {
  const allowed = {
    'lib/services/llm/model_routes.dart',
    'lib/services/db/repositories/model_repository.dart',
    'lib/screens/models/widgets/channel_edit_dialog.dart',
  };
  final read = RegExp(r'\b(?=[a-z_])\w*[cC]hannel\w*[!?]?\.(type|endpoint)\b');

  test('no one reads a channel\'s flat type or endpoint directly', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/l10n/') || allowed.contains(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        final code = line.split('//').first;
        if (read.hasMatch(code)) offenders.add('$path:${i + 1}  $line');
      }
    }
    expect(offenders, isEmpty,
        reason: 'read the model\'s route instead:\n  ${offenders.join('\n  ')}');
  });
}
