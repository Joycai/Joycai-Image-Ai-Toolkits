import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/screens/workbench/assistant/optimizer_config/preset_summary.dart';

void main() {
  test('takes the first prose paragraph, past a heading', () {
    expect(
      presetSummaryOf('# Role\n\nYou are a **portrait** prompt writer.\nKeep `names` intact.\n\n## Rules\n- one'),
      'You are a portrait prompt writer. Keep names intact.',
    );
  });

  test('strips list markers, quotes and links', () {
    expect(presetSummaryOf('> - See [the guide](https://x.y) first'), 'See the guide first');
    expect(presetSummaryOf('1. 识别画面主体'), '识别画面主体');
  });

  test('skips fences and rules; snake_case is left readable', () {
    expect(presetSummaryOf('---\n```\ncode\n```\n正文 一行'), '正文 一行');
  });

  test('nothing but structure is an empty summary', () {
    expect(presetSummaryOf('# Title\n\n---\n'), '');
    expect(presetSummaryOf(''), '');
  });
}
