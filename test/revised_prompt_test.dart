import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/protocol.dart';

/// Image surfaces that rewrite the prompt report what they actually drew
/// from (standard 13 §1); none of this app's protocols read it, and every
/// image response returned `text: ''`. Pinned against the documented shapes.
void main() {
  test('OpenAI Images: data[].revised_prompt (dall-e-3)', () {
    final body = jsonDecode('''
      {"created": 1, "data": [
        {"b64_json": "AAAA", "revised_prompt": "A watercolor fox at dusk, soft light."}
      ]}''') as Map<String, dynamic>;
    expect(revisedPromptFrom(body['data']),
        'A watercolor fox at dusk, soft light.');
  });

  test('gpt-image-1 reports none: empty, so the text stays empty', () {
    final body = jsonDecode('{"data": [{"b64_json": "AAAA"}]}')
        as Map<String, dynamic>;
    expect(revisedPromptFrom(body['data']), '');
  });

  test('DashScope async result: output.results[].actual_prompt', () {
    final body = jsonDecode('''
      {"output": {"task_status": "SUCCEEDED", "results": [
        {"orig_prompt": "hand-drawn poster",
         "actual_prompt": "Childhood-inspired hand-drawn poster design",
         "url": "https://example.invalid/x.png"}
      ]}}''') as Map<String, dynamic>;
    final output = body['output'] as Map;
    expect(revisedPromptFrom(output['results'], key: 'actual_prompt'),
        'Childhood-inspired hand-drawn poster design');
    // orig_prompt is what we sent, not a rewrite.
    expect(revisedPromptFrom(output['results']), '');
  });

  test('distinct rewrites are joined; identical ones collapse', () {
    final items = [
      {'revised_prompt': 'one'},
      {'revised_prompt': ' one '},
      {'revised_prompt': 'two'},
      {'revised_prompt': ''},
      'not a map',
    ];
    expect(revisedPromptFrom(items), 'one\n\ntwo');
  });

  test('a missing or malformed list is empty, never a throw', () {
    expect(revisedPromptFrom(null), '');
    expect(revisedPromptFrom({'revised_prompt': 'x'}), '');
  });
}
