import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_chat_protocol.dart';

/// A ④ base is normalised to its versioned root before `/messages` is
/// appended: the SDK-style base with no version gets `/v1`, a pasted request
/// URL loses its `/messages`, and every base that already worked is unchanged.
void main() {
  test('bases that already end in a version are untouched', () {
    for (final (base, url) in [
      ('https://api.anthropic.com/v1', 'https://api.anthropic.com/v1/messages'),
      ('https://api.minimaxi.com/anthropic/v1/', 'https://api.minimaxi.com/anthropic/v1/messages'),
      ('https://dashscope.aliyuncs.com/apps/anthropic/v1', 'https://dashscope.aliyuncs.com/apps/anthropic/v1/messages'),
      ('https://relay.example.com/v2', 'https://relay.example.com/v2/messages'),
    ]) {
      expect(anthropicMessagesUrl(base), url, reason: base);
    }
  });

  test('an SDK-style base without a version gets /v1', () {
    expect(anthropicMessagesUrl('https://api.anthropic.com'),
        'https://api.anthropic.com/v1/messages');
    expect(anthropicMessagesUrl('https://api.minimaxi.com/anthropic'),
        'https://api.minimaxi.com/anthropic/v1/messages');
  });

  test('a pasted request URL loses its /messages', () {
    expect(anthropicMessagesUrl('https://api.anthropic.com/v1/messages'),
        'https://api.anthropic.com/v1/messages');
    expect(anthropicApiBase('https://relay.example.com/v1/messages/'),
        'https://relay.example.com/v1');
  });
}
