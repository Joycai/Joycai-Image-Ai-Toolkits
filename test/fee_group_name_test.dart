import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/widgets/models/fee_group_row.dart';

/// The bracketed labels a group name carries become badges beside the name
/// on the fee-group row; this pins what counts as one.
void main() {
  void expectParts(String name, String base, List<String> tags) {
    final parts = parseFeeGroupName(name);
    expect(parts.base, base, reason: name);
    expect(parts.tags, tags, reason: name);
  }

  test('a leading bracket group is a tag and leaves the name clean', () {
    expectParts('[K]gemini-3.1-flash-image-preview', 'gemini-3.1-flash-image-preview', ['K']);
  });

  test('a trailing group, full-width brackets and several groups all count', () {
    expectParts('MinimaxH3[官方]', 'MinimaxH3', ['官方']);
    expectParts('Gemini Pro（特价）', 'Gemini Pro', ['特价']);
    expectParts('[特价kiro量]claude-opus-4-8 (relay)', 'claude-opus-4-8', ['特价kiro量', 'relay']);
  });

  test('a plain name has no tags, and a name that is only a bracket stays as typed', () {
    expectParts('Gemini Flash', 'Gemini Flash', []);
    expectParts('[官方]', '[官方]', []);
    expectParts('[ ]x', 'x', []);
  });

  test('unbalanced brackets are left alone', () {
    expectParts('gpt-image-2 [beta', 'gpt-image-2 [beta', []);
  });
}
