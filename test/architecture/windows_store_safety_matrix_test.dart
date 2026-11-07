import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/vendors/vendor_profile.dart';

void main() {
  test('Windows Store safety record covers every routable wire exactly once', () {
    final record = File('docs/testing/windows-store-ai-safety.md').readAsStringSync();
    final rows = RegExp(
      r'^\| `([^`]+)` \|',
      multiLine: true,
    ).allMatches(record).map((match) => match[1]!).toList();
    expect(rows, unorderedEquals(WireProtocol.values.map((wire) => wire.id)));
  });
}
