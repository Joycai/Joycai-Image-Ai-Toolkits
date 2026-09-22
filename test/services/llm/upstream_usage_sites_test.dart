import 'package:flutter_test/flutter_test.dart';
import 'package:joycai_image_ai_toolkits/services/llm/output_spec.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/anthropic_response.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/dashscope_chat_protocol.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/gemini_payload.dart';
import 'package:joycai_image_ai_toolkits/services/llm/protocols/openai_chat_parsing.dart';

/// Every place an upstream `usage` block is spread into response metadata
/// goes through `upstreamUsage`, so the two keys the app reserves for its
/// own conclusions — the provider-reported cost and the reference count —
/// cannot be set from the wire. The usage recorder reads them for every
/// vendor alike, and the reported cost zeroes every other part of a row's
/// cost, so a relay naming a field the same would dictate the bill.
///
/// The images protocols are pinned on the wire (`xai_images_protocol_test`);
/// these are the chat faces, which are pure functions.
void main() {
  const forged = {
    'prompt_tokens': 12,
    'input_tokens': 12,
    'promptTokenCount': 12,
    reportedCostKey: 99.0,
    inputImageCountKey: 7,
  };

  void expectClean(Map<String, dynamic>? metadata) {
    expect(metadata, isNotNull);
    expect(metadata!.containsKey(reportedCostKey), isFalse);
    expect(metadata.containsKey(inputImageCountKey), isFalse);
    expect(reportedCostOf(metadata), isNull);
    expect(inputImageCountOf(metadata), 0);
  }

  test('① chat: normalizeOpenAIUsage', () {
    final usage = normalizeOpenAIUsage(forged);
    expectClean(usage);
    expect(usage!['prompt_tokens'], 12);
  });

  test('DashScope chat, synchronous face: dashscopeChatMetadata', () {
    final metadata = dashscopeChatMetadata({'usage': forged, 'request_id': 'r'});
    expectClean(metadata);
    expect(metadata['prompt_tokens'], 12);
    expect(metadata['request_id'], 'r');
  });

  test('④: anthropicUsageMetadata', () {
    final metadata = anthropicUsageMetadata(forged);
    expectClean(metadata);
    // Its own conclusion is still drawn from the vendor's fields.
    expect(metadata['prompt_tokens'], 12);
  });

  test('③: every chunk parseGoogleChunks yields', () {
    final chunks = parseGoogleChunks({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'hi'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
      'usageMetadata': forged,
    }).toList();

    expect(chunks, isNotEmpty);
    for (final chunk in chunks) {
      if (chunk.metadata == null) continue;
      expectClean(chunk.metadata);
    }
    expect(chunks.any((c) => c.metadata?['promptTokenCount'] == 12), isTrue);
  });
}
