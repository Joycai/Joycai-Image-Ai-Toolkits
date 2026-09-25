import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/system/ui_prefs.dart';

/// A panel width is a `settings` row, and [UiPrefs] owns every one of those
/// keys. Four screens used to spell them out themselves inside an `initState`
/// / drag-end callback, which is both business logic in a widget and four
/// copies of a string users already have on disk — a typo in one of them loses
/// that panel's layout with nothing failing.
///
/// This is a source scan rather than a behaviour test on purpose: what it
/// guards is that a *fifth* copy never appears.
void main() {
  const owner = 'lib/services/system/ui_prefs.dart';

  test('the panel-width setting keys are spelled only in UiPrefs', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == owner) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final panel in UiPanel.values) {
          if (lines[i].contains(panel.settingKey)) {
            offenders.add('$path:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'ask AppState.uiPrefs instead of naming the key:\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}
